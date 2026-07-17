"""Application-backend contracts layered on top of the strict model API."""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from typing import Any, Mapping
from uuid import UUID

from .contracts import (
    IDENTIFIER_PATTERN,
    ParsedPredictionRequest,
    RECORD_FIELDS,
    REQUEST_SCHEMA_VERSION,
    RequestContractError,
    contract_issue,
    parse_prediction_request,
)


BACKEND_SCHEMA_VERSION = "1.0"
EVALUATION_REQUEST_FIELDS = {
    "schema_version",
    "request_id",
    "patient_id",
    "pregnancy_episode_id",
    "encounter_id",
    "model_input",
}
MODEL_INPUT_FIELDS = RECORD_FIELDS.difference({"record_id"})


@dataclass(frozen=True)
class EvaluationRequest:
    """Validated correlation IDs plus the exact model request to execute."""

    request_id: str
    patient_id: str
    pregnancy_episode_id: str
    encounter_id: str
    input_hash: str
    request_payload: dict[str, Any]
    prediction_request: ParsedPredictionRequest


def _uuid_value(value: Any, *, field: str) -> str:
    if not isinstance(value, str):
        raise RequestContractError(
            [contract_issue("invalid_identifier", field, f"{field} must be a UUID")]
        )
    try:
        return str(UUID(value))
    except (ValueError, AttributeError) as error:
        raise RequestContractError(
            [contract_issue("invalid_identifier", field, f"{field} must be a UUID")]
        ) from error


def parse_evaluation_request(payload: Any) -> EvaluationRequest:
    """Validate the app/backend envelope and construct a one-record ML batch.

    Missing or semantically invalid predictors remain record-level model
    errors. This lets the backend persist an explicit ``invalid_input`` result
    rather than silently converting incomplete information into score zero.
    """

    if not isinstance(payload, Mapping):
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_request_type",
                    None,
                    "Assessment evaluation request must be a JSON object",
                )
            ]
        )

    unknown = sorted(set(payload).difference(EVALUATION_REQUEST_FIELDS))
    missing = sorted(EVALUATION_REQUEST_FIELDS.difference(payload))
    errors = [
        contract_issue("unknown_field", field, f"Unknown request field: {field}")
        for field in unknown
    ]
    errors.extend(
        contract_issue("missing_field", field, f"Missing request field: {field}")
        for field in missing
    )
    if errors:
        raise RequestContractError(errors)

    if payload["schema_version"] != BACKEND_SCHEMA_VERSION:
        raise RequestContractError(
            [
                contract_issue(
                    "unsupported_schema_version",
                    "schema_version",
                    f"schema_version must be {BACKEND_SCHEMA_VERSION}",
                )
            ]
        )

    request_id = payload["request_id"]
    if (
        not isinstance(request_id, str)
        or IDENTIFIER_PATTERN.fullmatch(request_id) is None
    ):
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_identifier",
                    "request_id",
                    "request_id must use the versioned model identifier format",
                )
            ]
        )

    patient_id = _uuid_value(payload["patient_id"], field="patient_id")
    pregnancy_episode_id = _uuid_value(
        payload["pregnancy_episode_id"],
        field="pregnancy_episode_id",
    )
    encounter_id = _uuid_value(payload["encounter_id"], field="encounter_id")

    model_input = payload["model_input"]
    if not isinstance(model_input, Mapping):
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_type",
                    "model_input",
                    "model_input must be a JSON object",
                )
            ]
        )
    if "record_id" in model_input:
        raise RequestContractError(
            [
                contract_issue(
                    "unknown_field",
                    "model_input.record_id",
                    "record_id is owned by the backend and must not be submitted",
                )
            ]
        )

    model_record = dict(model_input)
    model_record["record_id"] = encounter_id
    model_payload = {
        "schema_version": REQUEST_SCHEMA_VERSION,
        "request_id": request_id,
        "records": [model_record],
    }
    prediction_request = parse_prediction_request(model_payload)
    canonical = json.dumps(
        model_record,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    return EvaluationRequest(
        request_id=request_id,
        patient_id=patient_id,
        pregnancy_episode_id=pregnancy_episode_id,
        encounter_id=encounter_id,
        input_hash=sha256(canonical).hexdigest(),
        request_payload=model_payload,
        prediction_request=prediction_request,
    )


__all__ = [
    "BACKEND_SCHEMA_VERSION",
    "EvaluationRequest",
    "MODEL_INPUT_FIELDS",
    "parse_evaluation_request",
]
