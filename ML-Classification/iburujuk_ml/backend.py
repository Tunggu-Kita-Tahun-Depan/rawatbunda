"""Protected RawatBunda backend for validated and persisted ML evaluation."""

from __future__ import annotations

import argparse
from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path
from typing import Any, Sequence

from fastapi import FastAPI, Request
from fastapi.responses import Response
from starlette.concurrency import run_in_threadpool
import uvicorn

from .api import (
    DEFAULT_MODEL_PATH,
    json_response,
    read_limited_json_body,
    request_error_status,
)
from .auth import (
    AuthenticationError,
    AuthenticationServiceError,
    AuthVerifier,
    StaticTokenVerifier,
    SupabaseAuthVerifier,
)
from .backend_contracts import BACKEND_SCHEMA_VERSION, EvaluationRequest, parse_evaluation_request
from .contracts import (
    RequestContractError,
    contract_issue,
    parse_json_document,
    serialize_json_document,
)
from .inference import DISCLAIMER, ModelRuntime, load_runtime, predict_request
from .persistence import (
    EncounterCorrelationError,
    InMemoryPredictionStore,
    JobClaim,
    PatientAccessDenied,
    PersistenceError,
    PredictionStore,
    RequestIdConflict,
    StoredPrediction,
    SupabasePredictionStore,
)
from .response_validation import (
    BackendResponseValidationError,
    validate_prediction_response,
)


LOGGER = logging.getLogger(__name__)


def backend_error_response(
    *,
    status: str,
    code: str,
    message: str,
    request_id: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "schema_version": BACKEND_SCHEMA_VERSION,
        "status": status,
        "errors": [contract_issue(code, None, message)],
        "clinical_review_still_required": True,
        "cannot_rule_out_maternal_risk": True,
        "may_not_downgrade_clinician_urgency": True,
        "may_not_suppress_referral": True,
        "disclaimer": DISCLAIMER,
    }
    if request_id is not None:
        payload["request_id"] = request_id
    return payload


def stored_evaluation_response(
    request: EvaluationRequest,
    claim: JobClaim,
    stored: StoredPrediction,
    model_response: dict[str, Any],
    *,
    idempotent_replay: bool,
) -> dict[str, Any]:
    """Return correlation metadata; the database remains the future UI source."""

    return {
        "schema_version": BACKEND_SCHEMA_VERSION,
        "status": "stored",
        "request_id": request.request_id,
        "job_id": stored.job_id,
        "prediction_id": stored.prediction_id,
        "patient_id": request.patient_id,
        "pregnancy_episode_id": request.pregnancy_episode_id,
        "encounter_id": request.encounter_id,
        "input_hash": request.input_hash,
        "idempotent_replay": idempotent_replay,
        "prediction": model_response["results"][0],
        "model": model_response["model"],
        "generated_at_utc": model_response["generated_at_utc"],
        "operational_priority_applied": False,
        "priority_snapshot_id": None,
        "next_action": "await_governed_priority_policy_and_bidan_confirmation",
    }


def _validated_model_response(
    runtime: ModelRuntime,
    evaluation: EvaluationRequest,
) -> dict[str, Any]:
    """Execute, round-trip through strict JSON, and validate before persistence."""

    produced = predict_request(runtime, evaluation.prediction_request)
    json_round_trip = parse_json_document(serialize_json_document(produced))
    return validate_prediction_response(
        json_round_trip,
        runtime=runtime,
        request_id=evaluation.request_id,
        record_id=evaluation.encounter_id,
    )


def create_app(
    *,
    model_path: str | Path = DEFAULT_MODEL_PATH,
    expected_sha256: str | None = None,
    runtime: ModelRuntime | None = None,
    store: PredictionStore | None = None,
    auth_verifier: AuthVerifier | None = None,
) -> FastAPI:
    """Create the app-facing backend with injectable test/local adapters."""

    configured_path = Path(model_path).expanduser().resolve()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        application.state.ready = False
        application.state.runtime = (
            runtime
            if runtime is not None
            else load_runtime(configured_path, expected_sha256=expected_sha256)
        )
        application.state.store = (
            store if store is not None else SupabasePredictionStore.from_environment()
        )
        application.state.auth_verifier = (
            auth_verifier
            if auth_verifier is not None
            else SupabaseAuthVerifier.from_environment()
        )
        application.state.ready = True
        try:
            yield
        finally:
            application.state.ready = False
            application.state.runtime = None
            application.state.store = None
            application.state.auth_verifier = None

    application = FastAPI(
        title="RawatBunda protected ML backend",
        version="1.0",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    @application.get("/health/live")
    async def liveness() -> Response:
        return json_response({"status": "alive"})

    @application.get("/health/ready")
    async def readiness(request: Request) -> Response:
        if not bool(getattr(request.app.state, "ready", False)):
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="backend_not_ready",
                    message="Backend is not ready",
                ),
                status_code=503,
            )
        loaded_runtime: ModelRuntime = request.app.state.runtime
        return json_response(
            {
                "status": "ready",
                "model_version": loaded_runtime.model_version,
                "artifact_sha256": loaded_runtime.artifact_sha256,
                "persistence": type(request.app.state.store).__name__,
            }
        )

    @application.post("/v1/assessments/evaluate")
    async def evaluate(request: Request) -> Response:
        if not bool(getattr(request.app.state, "ready", False)):
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="backend_not_ready",
                    message="Backend is not ready",
                ),
                status_code=503,
            )

        try:
            verifier: AuthVerifier = request.app.state.auth_verifier
            actor = await run_in_threadpool(
                verifier.verify,
                request.headers.get("authorization"),
            )
        except AuthenticationError as error:
            return json_response(
                backend_error_response(
                    status="unauthorized",
                    code="invalid_bearer_token",
                    message=str(error),
                ),
                status_code=401,
            )
        except AuthenticationServiceError:
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="identity_provider_unavailable",
                    message="Identity verification is unavailable",
                ),
                status_code=503,
            )
        if actor.role != "bidan":
            return json_response(
                backend_error_response(
                    status="forbidden",
                    code="bidan_role_required",
                    message="Only an authenticated bidan may request evaluation",
                ),
                status_code=403,
            )

        try:
            raw_body = await read_limited_json_body(request)
            evaluation = parse_evaluation_request(parse_json_document(raw_body))
        except RequestContractError as error:
            return json_response(
                {
                    "schema_version": BACKEND_SCHEMA_VERSION,
                    "status": "request_rejected",
                    "errors": list(error.errors),
                    "clinical_review_still_required": True,
                    "cannot_rule_out_maternal_risk": True,
                    "may_not_downgrade_clinician_urgency": True,
                    "may_not_suppress_referral": True,
                    "disclaimer": DISCLAIMER,
                },
                status_code=request_error_status(error),
            )

        loaded_runtime: ModelRuntime = request.app.state.runtime
        prediction_store: PredictionStore = request.app.state.store
        try:
            claim = await run_in_threadpool(
                prediction_store.claim_job,
                evaluation,
                actor_id=actor.user_id,
                model_version=loaded_runtime.model_version,
            )
        except RequestIdConflict as error:
            return json_response(
                backend_error_response(
                    status="conflict",
                    code="request_id_conflict",
                    message=str(error),
                    request_id=evaluation.request_id,
                ),
                status_code=409,
            )
        except EncounterCorrelationError as error:
            return json_response(
                backend_error_response(
                    status="conflict",
                    code="encounter_correlation_mismatch",
                    message=str(error),
                    request_id=evaluation.request_id,
                ),
                status_code=409,
            )
        except PatientAccessDenied as error:
            return json_response(
                backend_error_response(
                    status="forbidden",
                    code="patient_access_denied",
                    message=str(error),
                    request_id=evaluation.request_id,
                ),
                status_code=403,
            )
        except PersistenceError:
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="prediction_store_unavailable",
                    message="Prediction persistence is unavailable",
                    request_id=evaluation.request_id,
                ),
                status_code=503,
            )

        if not claim.claimed:
            if (
                claim.status == "completed"
                and claim.stored_response is not None
                and claim.prediction_id is not None
            ):
                try:
                    previous = validate_prediction_response(
                        claim.stored_response,
                        runtime=loaded_runtime,
                        request_id=evaluation.request_id,
                        record_id=evaluation.encounter_id,
                    )
                except BackendResponseValidationError:
                    LOGGER.exception("Stored model response failed validation")
                    return json_response(
                        backend_error_response(
                            status="service_unavailable",
                            code="stored_prediction_invalid",
                            message="Stored prediction failed integrity validation",
                            request_id=evaluation.request_id,
                        ),
                        status_code=503,
                    )
                return json_response(
                    stored_evaluation_response(
                        evaluation,
                        claim,
                        StoredPrediction(claim.job_id, claim.prediction_id),
                        previous,
                        idempotent_replay=True,
                    )
                )
            return json_response(
                backend_error_response(
                    status="conflict",
                    code="request_in_progress",
                    message="The same request_id is already being processed",
                    request_id=evaluation.request_id,
                ),
                status_code=409,
            )

        try:
            model_response = await run_in_threadpool(
                _validated_model_response,
                loaded_runtime,
                evaluation,
            )
            stored = await run_in_threadpool(
                prediction_store.complete_job,
                claim,
                evaluation,
                actor_id=actor.user_id,
                model_response=model_response,
            )
        except Exception as error:
            # The broad branch includes scorer and persistence failures. The
            # job is explicitly failed; no score-zero fallback is permitted.
            code = (
                "model_response_invalid"
                if isinstance(error, BackendResponseValidationError)
                else "evaluation_failed"
            )
            try:
                await run_in_threadpool(
                    prediction_store.fail_job,
                    claim,
                    code=code,
                    message="Evaluation or durable persistence failed",
                )
            except PersistenceError:
                LOGGER.exception("Failed to persist ML job failure")
            LOGGER.exception("Assessment evaluation failed")
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code=code,
                    message="Evaluation could not be stored safely",
                    request_id=evaluation.request_id,
                ),
                status_code=503,
            )

        return json_response(
            stored_evaluation_response(
                evaluation,
                claim,
                stored,
                model_response,
                idempotent_replay=False,
            ),
            status_code=201,
        )

    return application


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model",
        default=os.environ.get("IBURUJUK_MODEL_PATH", str(DEFAULT_MODEL_PATH)),
    )
    parser.add_argument(
        "--expected-sha256",
        default=os.environ.get("IBURUJUK_MODEL_SHA256"),
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--in-memory", action="store_true")
    parser.add_argument("--dev-token", default=os.environ.get("RAWATBUNDA_DEV_TOKEN"))
    parser.add_argument(
        "--dev-user-id",
        default=os.environ.get(
            "RAWATBUNDA_DEV_USER_ID",
            "00000000-0000-4000-8000-000000000001",
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    store: PredictionStore | None = None
    verifier: AuthVerifier | None = None
    if args.in_memory:
        if not args.dev_token:
            raise SystemExit("--dev-token is required with --in-memory")
        store = InMemoryPredictionStore()
        verifier = StaticTokenVerifier(
            args.dev_token,
            user_id=args.dev_user_id,
            role="bidan",
        )
    elif not args.expected_sha256:
        raise SystemExit(
            "IBURUJUK_MODEL_SHA256 or --expected-sha256 is required in production"
        )
    uvicorn.run(
        create_app(
            model_path=args.model,
            expected_sha256=args.expected_sha256,
            store=store,
            auth_verifier=verifier,
        ),
        host=args.host,
        port=args.port,
        access_log=False,
        proxy_headers=False,
        server_header=False,
        date_header=False,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = ["create_app", "main", "stored_evaluation_response"]
