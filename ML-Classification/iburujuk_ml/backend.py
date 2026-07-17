"""Protected RawatBunda backend for validated and persisted ML evaluation."""

from __future__ import annotations

import argparse
from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path
from typing import Any, Sequence
from uuid import UUID

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
    AuthenticatedActor,
    AuthVerifier,
    StaticTokenVerifier,
    SupabaseAuthVerifier,
)
from .backend_contracts import BACKEND_SCHEMA_VERSION, EvaluationRequest, parse_evaluation_request
from .clinical_contracts import (
    ConfirmationRequest,
    parse_confirmation_request,
    parse_patient_create_request,
)
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
from .stt import (
    ALLOWED_AUDIO_TYPES,
    MAX_AUDIO_BYTES,
    GroqSpeechToTextService,
    SpeechToTextService,
    SttServiceError,
)


LOGGER = logging.getLogger(__name__)


async def read_limited_audio_body(request: Request) -> bytes:
    declared = request.headers.get("content-length")
    if declared is not None:
        try:
            if int(declared) > MAX_AUDIO_BYTES:
                raise RequestContractError(
                    [contract_issue("audio_too_large", None, "Audio must not exceed 10 MiB")]
                )
        except ValueError as error:
            raise RequestContractError(
                [contract_issue("invalid_content_length", None, "Invalid Content-Length")]
            ) from error
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > MAX_AUDIO_BYTES:
            raise RequestContractError(
                [contract_issue("audio_too_large", None, "Audio must not exceed 10 MiB")]
            )
    if not body:
        raise RequestContractError(
            [contract_issue("empty_audio", None, "Audio body must not be empty")]
        )
    return bytes(body)


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


def confirmed_assessment_response(
    confirmation: ConfirmationRequest,
    *,
    job_id: str,
    prediction_id: str | None,
    model_response: dict[str, Any] | None,
    priority: Any,
    idempotent_replay: bool,
    ml_error: str | None = None,
) -> dict[str, Any]:
    """Return write correlation while keeping Supabase as UI source of truth."""

    evaluation = confirmation.evaluation
    return {
        "schema_version": BACKEND_SCHEMA_VERSION,
        "status": "stored" if model_response is not None else "stored_with_ml_failure",
        "request_id": evaluation.request_id,
        "job_id": job_id,
        "prediction_id": prediction_id,
        "patient_id": evaluation.patient_id,
        "pregnancy_episode_id": evaluation.pregnancy_episode_id,
        "encounter_id": evaluation.encounter_id,
        "stt_draft_id": confirmation.stt_draft_id,
        "input_hash": evaluation.input_hash,
        "idempotent_replay": idempotent_replay or priority.idempotent_replay,
        "prediction": (
            model_response["results"][0] if model_response is not None else None
        ),
        "model": model_response.get("model") if model_response is not None else None,
        "ml_error": ml_error,
        "operational_priority_applied": True,
        "priority": {
            "priority_snapshot_id": priority.priority_snapshot_id,
            "final_band": priority.final_band,
            "needs_verification": priority.needs_verification,
            "reasons": priority.reasons,
            "missing_inputs": priority.missing_inputs,
            "generated_at": priority.generated_at,
        },
        "database_source_of_truth": True,
        "next_action": "read_current_priority_snapshots",
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
    stt_service: SpeechToTextService | None = None,
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
        application.state.stt_service = stt_service
        if application.state.stt_service is None and os.environ.get("GROQ_API_KEY", "").strip():
            application.state.stt_service = GroqSpeechToTextService.from_environment()
        application.state.ready = True
        try:
            yield
        finally:
            application.state.ready = False
            application.state.runtime = None
            application.state.store = None
            application.state.auth_verifier = None
            application.state.stt_service = None

    application = FastAPI(
        title="RawatBunda protected ML backend",
        version="1.0",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    async def authenticate_bidan(
        request: Request,
    ) -> tuple[AuthenticatedActor | None, Response | None]:
        try:
            verifier: AuthVerifier = request.app.state.auth_verifier
            actor = await run_in_threadpool(
                verifier.verify,
                request.headers.get("authorization"),
            )
        except AuthenticationError as error:
            return None, json_response(
                backend_error_response(
                    status="unauthorized",
                    code="invalid_bearer_token",
                    message=str(error),
                ),
                status_code=401,
            )
        except AuthenticationServiceError:
            return None, json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="identity_provider_unavailable",
                    message="Identity verification is unavailable",
                ),
                status_code=503,
            )
        if actor.role != "bidan":
            return None, json_response(
                backend_error_response(
                    status="forbidden",
                    code="bidan_role_required",
                    message="Only an authenticated bidan may use this workflow",
                ),
                status_code=403,
            )
        return actor, None

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
                "stt_available": request.app.state.stt_service is not None,
            }
        )

    @application.post("/v1/patients")
    async def create_patient(request: Request) -> Response:
        actor, auth_error = await authenticate_bidan(request)
        if auth_error is not None:
            return auth_error
        assert actor is not None
        try:
            raw_body = await read_limited_json_body(request)
            patient_request = parse_patient_create_request(parse_json_document(raw_body))
            prediction_store: PredictionStore = request.app.state.store
            created = await run_in_threadpool(
                prediction_store.create_patient,
                patient_request,
                actor_id=actor.user_id,
            )
        except RequestContractError as error:
            return json_response(
                {
                    "schema_version": BACKEND_SCHEMA_VERSION,
                    "status": "request_rejected",
                    "errors": list(error.errors),
                },
                status_code=request_error_status(error),
            )
        except PersistenceError:
            LOGGER.exception("Patient creation failed")
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="patient_store_unavailable",
                    message="Patient could not be stored",
                ),
                status_code=503,
            )
        return json_response(
            {
                "schema_version": BACKEND_SCHEMA_VERSION,
                "status": "stored",
                "patient_id": created.patient_id,
                "pregnancy_episode_id": created.pregnancy_episode_id,
                "database_source_of_truth": True,
            },
            status_code=201,
        )

    @application.post("/v1/stt/drafts")
    async def create_stt_draft(request: Request) -> Response:
        actor, auth_error = await authenticate_bidan(request)
        if auth_error is not None:
            return auth_error
        assert actor is not None
        service: SpeechToTextService | None = request.app.state.stt_service
        if service is None:
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="stt_not_configured",
                    message="Speech-to-text is not configured",
                ),
                status_code=503,
            )
        content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        if content_type not in ALLOWED_AUDIO_TYPES:
            return json_response(
                backend_error_response(
                    status="request_rejected",
                    code="unsupported_audio_type",
                    message="Unsupported audio Content-Type",
                ),
                status_code=415,
            )
        try:
            patient_id = str(UUID(request.query_params.get("patient_id", "")))
            episode_id = str(UUID(request.query_params.get("pregnancy_episode_id", "")))
        except ValueError:
            return json_response(
                backend_error_response(
                    status="request_rejected",
                    code="invalid_identifier",
                    message="patient_id and pregnancy_episode_id must be UUIDs",
                ),
                status_code=422,
            )
        filename = Path(request.headers.get("x-audio-filename", "recording.wav")).name[:255]
        prediction_store: PredictionStore = request.app.state.store
        try:
            await run_in_threadpool(
                prediction_store.assert_access,
                patient_id=patient_id,
                pregnancy_episode_id=episode_id,
                actor_id=actor.user_id,
            )
            audio = await read_limited_audio_body(request)
            extraction = await run_in_threadpool(
                service.transcribe_and_extract,
                filename=filename,
                content_type=content_type,
                audio=audio,
            )
            stored = await run_in_threadpool(
                prediction_store.create_stt_draft,
                patient_id=patient_id,
                pregnancy_episode_id=episode_id,
                actor_id=actor.user_id,
                extraction=extraction,
                audio_metadata={
                    "filename": filename,
                    "content_type": content_type,
                    "byte_length": len(audio),
                    "audio_retained": False,
                },
            )
        except RequestContractError as error:
            return json_response(
                {
                    "schema_version": BACKEND_SCHEMA_VERSION,
                    "status": "request_rejected",
                    "errors": list(error.errors),
                },
                status_code=413,
            )
        except PatientAccessDenied as error:
            return json_response(
                backend_error_response(
                    status="forbidden",
                    code="patient_access_denied",
                    message=str(error),
                ),
                status_code=403,
            )
        except EncounterCorrelationError as error:
            return json_response(
                backend_error_response(
                    status="conflict",
                    code="pregnancy_episode_correlation_mismatch",
                    message=str(error),
                ),
                status_code=409,
            )
        except SttServiceError:
            LOGGER.exception("STT draft generation failed")
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="stt_processing_failed",
                    message="Audio could not be converted into a safe draft",
                ),
                status_code=503,
            )
        except PersistenceError:
            LOGGER.exception("STT draft persistence failed")
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="draft_store_unavailable",
                    message="STT draft could not be stored",
                ),
                status_code=503,
            )
        return json_response(
            {
                "schema_version": BACKEND_SCHEMA_VERSION,
                "status": "pending_bidan_review",
                "draft_id": stored.draft_id,
                "patient_id": patient_id,
                "pregnancy_episode_id": episode_id,
                "transcript": extraction.transcript,
                "model_input": extraction.model_input,
                "clinical_context": extraction.clinical_context,
                "soap_note": extraction.soap_note,
                "warnings": extraction.warnings,
                "generated_at": extraction.generated_at,
                "audio_retained": False,
                "requires_bidan_confirmation": True,
            },
            status_code=201,
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

    @application.post("/v1/assessments/confirm")
    async def confirm_assessment(request: Request) -> Response:
        actor, auth_error = await authenticate_bidan(request)
        if auth_error is not None:
            return auth_error
        assert actor is not None
        try:
            raw_body = await read_limited_json_body(request)
            confirmation = parse_confirmation_request(parse_json_document(raw_body))
        except RequestContractError as error:
            return json_response(
                {
                    "schema_version": BACKEND_SCHEMA_VERSION,
                    "status": "request_rejected",
                    "errors": list(error.errors),
                    "clinical_review_still_required": True,
                },
                status_code=request_error_status(error),
            )

        evaluation = confirmation.evaluation
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
                    code="assessment_store_unavailable",
                    message="Confirmed assessment could not be registered",
                    request_id=evaluation.request_id,
                ),
                status_code=503,
            )

        model_response: dict[str, Any] | None = None
        prediction_id: str | None = None
        replay = not claim.claimed
        if replay:
            if (
                claim.status != "completed"
                or claim.stored_response is None
                or claim.prediction_id is None
            ):
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
                model_response = validate_prediction_response(
                    claim.stored_response,
                    runtime=loaded_runtime,
                    request_id=evaluation.request_id,
                    record_id=evaluation.encounter_id,
                )
                prediction_id = claim.prediction_id
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
        else:
            try:
                model_response = await run_in_threadpool(
                    _validated_model_response,
                    loaded_runtime,
                    evaluation,
                )
                stored_prediction = await run_in_threadpool(
                    prediction_store.complete_job,
                    claim,
                    evaluation,
                    actor_id=actor.user_id,
                    model_response=model_response,
                )
                prediction_id = stored_prediction.prediction_id
            except Exception as error:
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
                        message="Evaluation or durable prediction persistence failed",
                    )
                except PersistenceError:
                    LOGGER.exception("Failed to persist ML job failure")
                LOGGER.exception(
                    "ML failed after encounter registration; finalizing rules-only priority"
                )
                model_response = None
                prediction_id = None

        try:
            priority = await run_in_threadpool(
                prediction_store.finalize_assessment,
                confirmation,
                actor_id=actor.user_id,
                prediction_id=prediction_id,
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
        except EncounterCorrelationError as error:
            return json_response(
                backend_error_response(
                    status="conflict",
                    code="workflow_correlation_mismatch",
                    message=str(error),
                    request_id=evaluation.request_id,
                ),
                status_code=409,
            )
        except PersistenceError:
            LOGGER.exception("Confirmed assessment finalization failed")
            return json_response(
                backend_error_response(
                    status="service_unavailable",
                    code="priority_store_unavailable",
                    message="Encounter exists but operational priority could not be stored",
                    request_id=evaluation.request_id,
                ),
                status_code=503,
            )

        return json_response(
            confirmed_assessment_response(
                confirmation,
                job_id=claim.job_id,
                prediction_id=prediction_id,
                model_response=model_response,
                priority=priority,
                idempotent_replay=replay,
                ml_error=("evaluation_failed" if model_response is None else None),
            ),
            status_code=200 if replay else 201,
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
