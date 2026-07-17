"""Defense-in-depth validation for model responses before database writes."""

from __future__ import annotations

from datetime import datetime
import math
from numbers import Real
from typing import Any, Mapping

from .contracts import RESPONSE_SCHEMA_VERSION
from .inference import ModelRuntime


TOP_LEVEL_FIELDS = {
    "schema_version",
    "request_id",
    "generated_at_utc",
    "model",
    "results",
}
MODEL_FIELDS = {
    "model_version",
    "artifact_sha256",
    "algorithm",
    "operating_threshold",
    "score_definition",
    "ranking_policy",
}
RESULT_FIELDS = {
    "record_id",
    "status",
    "model_score",
    "risk_signal",
    "risk_band",
    "ranking_eligible",
    "score_comparable_within_artifact",
    "ranking_blockers",
    "measurement_timestamp",
    "errors",
    "warnings",
    "clinical_review_still_required",
    "cannot_rule_out_maternal_risk",
    "may_not_downgrade_clinician_urgency",
    "may_not_suppress_referral",
    "disclaimer",
}


class BackendResponseValidationError(ValueError):
    """The model returned a response that the backend must not persist."""


def _exact_fields(value: Any, expected: set[str], *, name: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise BackendResponseValidationError(f"{name} must be an object")
    actual = set(value)
    if actual != expected:
        raise BackendResponseValidationError(
            f"{name} fields differ from the approved schema: "
            f"missing={sorted(expected - actual)}, unknown={sorted(actual - expected)}"
        )
    return value


def _timestamp(value: Any, *, name: str) -> str:
    if not isinstance(value, str):
        raise BackendResponseValidationError(f"{name} must be a timestamp string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise BackendResponseValidationError(f"{name} is not a valid timestamp") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise BackendResponseValidationError(f"{name} must include a timezone")
    return value


def _finite_probability(value: Any, *, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, Real):
        raise BackendResponseValidationError(f"{name} must be a number")
    parsed = float(value)
    if not math.isfinite(parsed) or not 0.0 <= parsed <= 1.0:
        raise BackendResponseValidationError(f"{name} must be finite within [0, 1]")
    return parsed


def validate_prediction_response(
    response: Any,
    *,
    runtime: ModelRuntime,
    request_id: str,
    record_id: str,
) -> dict[str, Any]:
    """Validate correlation, release identity, safety flags, and score semantics."""

    root = _exact_fields(response, TOP_LEVEL_FIELDS, name="response")
    if root["schema_version"] != RESPONSE_SCHEMA_VERSION:
        raise BackendResponseValidationError("Unexpected response schema_version")
    if root["request_id"] != request_id:
        raise BackendResponseValidationError("Model response request_id mismatch")
    _timestamp(root["generated_at_utc"], name="generated_at_utc")

    model = _exact_fields(root["model"], MODEL_FIELDS, name="model")
    if model["model_version"] != runtime.model_version:
        raise BackendResponseValidationError("Model version mismatch")
    if model["artifact_sha256"] != runtime.artifact_sha256:
        raise BackendResponseValidationError("Artifact SHA-256 mismatch")
    if model["algorithm"] != runtime.model_name:
        raise BackendResponseValidationError("Model algorithm mismatch")
    threshold = _finite_probability(
        model["operating_threshold"],
        name="operating_threshold",
    )
    if threshold != runtime.threshold:
        raise BackendResponseValidationError("Model threshold mismatch")
    if model["score_definition"] != "source-high-label-pattern-score":
        raise BackendResponseValidationError("Unsupported score definition")
    if not isinstance(model["ranking_policy"], str) or not model["ranking_policy"]:
        raise BackendResponseValidationError("ranking_policy must be non-empty")

    results = root["results"]
    if not isinstance(results, list) or len(results) != 1:
        raise BackendResponseValidationError("Exactly one correlated result is required")
    result = _exact_fields(results[0], RESULT_FIELDS, name="result")
    if result["record_id"] != record_id:
        raise BackendResponseValidationError("Model response record_id mismatch")
    if result["ranking_eligible"] is not False:
        raise BackendResponseValidationError("Shadow model may not authorize ranking")
    blockers = result["ranking_blockers"]
    if not isinstance(blockers, list) or not blockers or not all(
        isinstance(item, str) and item for item in blockers
    ):
        raise BackendResponseValidationError("ranking_blockers must be non-empty")
    for safety_flag in (
        "clinical_review_still_required",
        "cannot_rule_out_maternal_risk",
        "may_not_downgrade_clinician_urgency",
        "may_not_suppress_referral",
    ):
        if result[safety_flag] is not True:
            raise BackendResponseValidationError(f"Missing safety flag: {safety_flag}")
    if not isinstance(result["disclaimer"], str) or not result["disclaimer"]:
        raise BackendResponseValidationError("Result disclaimer must be non-empty")
    if not isinstance(result["errors"], list) or not isinstance(result["warnings"], list):
        raise BackendResponseValidationError("errors and warnings must be arrays")

    status = result["status"]
    if status == "ok":
        score = _finite_probability(result["model_score"], name="model_score")
        signal = result["risk_signal"]
        if not isinstance(signal, bool) or signal != (score >= threshold):
            raise BackendResponseValidationError("risk_signal is inconsistent with score")
        expected_band = (
            "high-label-pattern-detected"
            if signal
            else "high-label-pattern-not-detected"
        )
        if result["risk_band"] != expected_band:
            raise BackendResponseValidationError("risk_band is inconsistent with score")
        if result["score_comparable_within_artifact"] is not True:
            raise BackendResponseValidationError("Valid score must be artifact-comparable")
        if result["errors"]:
            raise BackendResponseValidationError("Valid score may not contain errors")
        _timestamp(result["measurement_timestamp"], name="measurement_timestamp")
    elif status in {"invalid_input", "out_of_distribution"}:
        if any(
            result[field] is not None
            for field in ("model_score", "risk_signal", "risk_band")
        ):
            raise BackendResponseValidationError("Abstained result must not contain a score")
        if result["score_comparable_within_artifact"] is not False:
            raise BackendResponseValidationError("Abstained result is not comparable")
        if not result["errors"]:
            raise BackendResponseValidationError("Abstained result requires errors")
        if result["measurement_timestamp"] is not None:
            _timestamp(result["measurement_timestamp"], name="measurement_timestamp")
    else:
        raise BackendResponseValidationError(f"Unsupported prediction status: {status}")

    return {
        "schema_version": root["schema_version"],
        "request_id": root["request_id"],
        "generated_at_utc": root["generated_at_utc"],
        "model": dict(model),
        "results": [dict(result)],
    }


__all__ = ["BackendResponseValidationError", "validate_prediction_response"]
