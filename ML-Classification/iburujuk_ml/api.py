"""Internal HTTP boundary for the maternal-risk shadow model.

This service exposes the strict model JSON contract only. Application clients
should call :mod:`iburujuk_ml.backend`, which adds authentication, correlation,
response validation, and durable persistence.
"""

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

from .contracts import (
    MAX_JSON_BYTES,
    RESPONSE_SCHEMA_VERSION,
    RequestContractError,
    contract_issue,
    serialize_json_document,
)
from .inference import (
    DISCLAIMER,
    ModelRuntime,
    load_runtime,
    predict_json,
    request_error_response,
)


LOGGER = logging.getLogger(__name__)
ML_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL_PATH = ML_ROOT / "artifacts" / "maternal_risk_model.joblib"
JSON_HEADERS = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
}


def json_response(payload: Any, *, status_code: int = 200) -> Response:
    """Return one strict JSON document with privacy-safe response headers."""

    return Response(
        content=serialize_json_document(payload),
        status_code=status_code,
        media_type="application/json",
        headers=JSON_HEADERS,
    )


def json_text_response(value: str, *, status_code: int = 200) -> Response:
    """Return JSON already serialized by the strict model contract."""

    return Response(
        content=value,
        status_code=status_code,
        media_type="application/json",
        headers=JSON_HEADERS,
    )


def service_unavailable_response(message: str) -> dict[str, Any]:
    """Build a fail-closed response for an unavailable model runtime."""

    return {
        "schema_version": RESPONSE_SCHEMA_VERSION,
        "status": "service_unavailable",
        "errors": [
            contract_issue("model_service_unavailable", None, message),
        ],
        "clinical_review_still_required": True,
        "cannot_rule_out_maternal_risk": True,
        "may_not_downgrade_clinician_urgency": True,
        "may_not_suppress_referral": True,
        "disclaimer": DISCLAIMER,
    }


def request_error_status(error: RequestContractError) -> int:
    codes = {str(issue.get("code", "")) for issue in error.errors}
    if "request_too_large" in codes:
        return 413
    if codes & {"unsupported_media_type", "unsupported_content_encoding"}:
        return 415
    if "invalid_content_length" in codes:
        return 400
    return 422


async def read_limited_json_body(request: Request) -> bytes:
    """Read JSON without allowing the web framework to normalize it first."""

    content_type = request.headers.get("content-type", "")
    media_type = content_type.split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise RequestContractError(
            [
                contract_issue(
                    "unsupported_media_type",
                    None,
                    "Content-Type must be application/json",
                )
            ]
        )

    content_encoding = request.headers.get("content-encoding", "identity").lower()
    if content_encoding not in {"", "identity"}:
        raise RequestContractError(
            [
                contract_issue(
                    "unsupported_content_encoding",
                    None,
                    "Compressed request bodies are not accepted",
                )
            ]
        )

    declared_length = request.headers.get("content-length")
    if declared_length is not None:
        try:
            parsed_length = int(declared_length)
        except ValueError as error:
            raise RequestContractError(
                [
                    contract_issue(
                        "invalid_content_length",
                        None,
                        "Content-Length must be a non-negative integer",
                    )
                ]
            ) from error
        if parsed_length < 0:
            raise RequestContractError(
                [
                    contract_issue(
                        "invalid_content_length",
                        None,
                        "Content-Length must be a non-negative integer",
                    )
                ]
            )
        if parsed_length > MAX_JSON_BYTES:
            raise RequestContractError(
                [
                    contract_issue(
                        "request_too_large",
                        None,
                        f"JSON request must not exceed {MAX_JSON_BYTES} bytes",
                    )
                ]
            )

    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > MAX_JSON_BYTES:
            raise RequestContractError(
                [
                    contract_issue(
                        "request_too_large",
                        None,
                        f"JSON request must not exceed {MAX_JSON_BYTES} bytes",
                    )
                ]
            )
    return bytes(body)


def create_app(
    *,
    model_path: str | Path = DEFAULT_MODEL_PATH,
    expected_sha256: str | None = None,
    runtime: ModelRuntime | None = None,
) -> FastAPI:
    """Create the internal model-only service."""

    configured_path = Path(model_path).expanduser().resolve()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        application.state.ready = False
        application.state.runtime = (
            runtime
            if runtime is not None
            else load_runtime(configured_path, expected_sha256=expected_sha256)
        )
        application.state.ready = True
        try:
            yield
        finally:
            application.state.ready = False
            application.state.runtime = None

    application = FastAPI(
        title="RawatBunda internal maternal-risk model",
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
                service_unavailable_response("Model service is not ready"),
                status_code=503,
            )
        loaded_runtime: ModelRuntime = request.app.state.runtime
        return json_response(
            {
                "status": "ready",
                "model_version": loaded_runtime.model_version,
                "artifact_sha256": loaded_runtime.artifact_sha256,
            }
        )

    @application.post("/v1/predict")
    async def predict(request: Request) -> Response:
        if not bool(getattr(request.app.state, "ready", False)):
            return json_response(
                service_unavailable_response("Model service is not ready"),
                status_code=503,
            )
        try:
            raw_body = await read_limited_json_body(request)
            loaded_runtime: ModelRuntime = request.app.state.runtime
            rendered = await run_in_threadpool(
                predict_json,
                loaded_runtime,
                raw_body,
            )
        except RequestContractError as error:
            return json_response(
                request_error_response(error),
                status_code=request_error_status(error),
            )
        except Exception:
            request.app.state.ready = False
            LOGGER.exception("Model scoring failed; service marked unready")
            return json_response(
                service_unavailable_response("Model execution failed"),
                status_code=503,
            )
        return json_text_response(rendered)

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
    parser.add_argument("--port", type=int, default=8000)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    uvicorn.run(
        create_app(model_path=args.model, expected_sha256=args.expected_sha256),
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


__all__ = [
    "DEFAULT_MODEL_PATH",
    "create_app",
    "json_response",
    "read_limited_json_body",
    "service_unavailable_response",
]
