"""Versioned, strict JSON boundary between the model and application backend."""

from __future__ import annotations

from dataclasses import dataclass
import json
import math
from numbers import Real
import re
from typing import Any, Mapping, Sequence

import pandas as pd


# ---------------------------------------------------------------------------
# Public API schema
# ---------------------------------------------------------------------------

REQUEST_SCHEMA_VERSION = "1.0"
RESPONSE_SCHEMA_VERSION = "1.0"
MAX_BATCH_SIZE = 100
MAX_JSON_BYTES = 1_048_576
MAX_JSON_DEPTH = 32
MAX_JSON_NUMBER_CHARACTERS = 128
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")

RECORD_FIELDS = {
    "record_id",
    "measured_at",
    "age_years",
    "systolic_bp_mmhg",
    "diastolic_bp_mmhg",
    "blood_sugar",
    "body_temperature",
    "bmi_kg_m2",
    "previous_complications",
    "preexisting_diabetes",
    "gestational_diabetes",
    "mental_health_indicator",
    "heart_rate_bpm",
}

NUMERIC_FIELDS_TO_MODEL = {
    "age_years": "Age",
    "systolic_bp_mmhg": "Systolic BP",
    "diastolic_bp_mmhg": "Diastolic",
    "bmi_kg_m2": "BMI",
    "heart_rate_bpm": "Heart Rate",
}

BOOLEAN_FIELDS_TO_MODEL = {
    "previous_complications": "Previous Complications",
    "preexisting_diabetes": "Preexisting Diabetes",
    "gestational_diabetes": "Gestational Diabetes",
    "mental_health_indicator": "Mental Health",
}


@dataclass(frozen=True)
class ParsedPredictionRequest:
    """Validated envelope plus per-record contract issues and model input rows."""

    request_id: str
    record_ids: tuple[str, ...]
    frame: pd.DataFrame
    record_errors: tuple[tuple[dict[str, Any], ...], ...]


class RequestContractError(ValueError):
    """A request-level error that prevents safe record correlation."""

    def __init__(self, errors: Sequence[dict[str, Any]]):
        self.errors = tuple(dict(error) for error in errors)
        super().__init__("Invalid prediction request")


def contract_issue(
    code: str,
    field: str | None,
    message: str,
) -> dict[str, Any]:
    """Return a stable, JSON-safe contract issue."""

    return {"code": code, "field": field, "message": message}


# ---------------------------------------------------------------------------
# Strict JSON parsing and serialization
# ---------------------------------------------------------------------------

def parse_json_document(raw: str | bytes) -> Any:
    """Parse standards-compliant JSON; reject NaN, Infinity, and duplicate keys."""

    if isinstance(raw, bytes):
        if len(raw) > MAX_JSON_BYTES:
            raise RequestContractError(
                [
                    contract_issue(
                        "request_too_large",
                        None,
                        f"JSON request must not exceed {MAX_JSON_BYTES} bytes",
                    )
                ]
            )
        try:
            raw = raw.decode("utf-8", errors="strict")
        except UnicodeDecodeError as error:
            raise RequestContractError(
                [contract_issue("invalid_encoding", None, "JSON must be UTF-8")]
            ) from error
    if not isinstance(raw, str):
        raise TypeError("raw JSON must be str or bytes")
    try:
        raw_size = len(raw.encode("utf-8", errors="strict"))
    except UnicodeEncodeError as error:
        raise RequestContractError(
            [contract_issue("invalid_encoding", None, "JSON must contain valid UTF-8 text")]
        ) from error
    if raw_size > MAX_JSON_BYTES:
        raise RequestContractError(
            [
                contract_issue(
                    "request_too_large",
                    None,
                    f"JSON request must not exceed {MAX_JSON_BYTES} bytes",
                )
            ]
        )

    def reject_constant(value: str) -> None:
        raise RequestContractError(
            [
                contract_issue(
                    "non_finite_number",
                    None,
                    f"JSON numeric constant {value} is not permitted",
                )
            ]
        )

    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise RequestContractError(
                    [
                        contract_issue(
                            "duplicate_json_key",
                            key,
                            f"Duplicate JSON key: {key}",
                        )
                    ]
                )
            result[key] = value
        return result

    def parse_integer_token(token: str) -> int:
        if len(token) > MAX_JSON_NUMBER_CHARACTERS:
            raise RequestContractError(
                [
                    contract_issue(
                        "number_token_too_long",
                        None,
                        "JSON numeric tokens must not exceed "
                        f"{MAX_JSON_NUMBER_CHARACTERS} characters",
                    )
                ]
            )
        return int(token)

    def parse_float_token(token: str) -> float:
        if len(token) > MAX_JSON_NUMBER_CHARACTERS:
            raise RequestContractError(
                [
                    contract_issue(
                        "number_token_too_long",
                        None,
                        "JSON numeric tokens must not exceed "
                        f"{MAX_JSON_NUMBER_CHARACTERS} characters",
                    )
                ]
            )
        value = float(token)
        if not math.isfinite(value):
            raise RequestContractError(
                [
                    contract_issue(
                        "non_finite_number",
                        None,
                        "JSON numbers must be finite",
                    )
                ]
            )
        return value

    try:
        parsed = json.loads(
            raw,
            parse_constant=reject_constant,
            parse_int=parse_integer_token,
            parse_float=parse_float_token,
            object_pairs_hook=reject_duplicate_keys,
        )
    except RequestContractError:
        raise
    except json.JSONDecodeError as error:
        raise RequestContractError(
            [
                contract_issue(
                    "malformed_json",
                    None,
                    f"Malformed JSON at line {error.lineno}, column {error.colno}",
                )
            ]
        ) from error
    except RecursionError as error:
        raise RequestContractError(
            [contract_issue("json_too_deep", None, "JSON nesting is too deep")]
        ) from error
    except ValueError as error:
        raise RequestContractError(
            [contract_issue("malformed_json", None, "JSON contains an invalid number")]
        ) from error

    stack: list[tuple[Any, int]] = [(parsed, 1)]
    while stack:
        value, depth = stack.pop()
        if depth > MAX_JSON_DEPTH:
            raise RequestContractError(
                [
                    contract_issue(
                        "json_too_deep",
                        None,
                        f"JSON nesting must not exceed {MAX_JSON_DEPTH} levels",
                    )
                ]
            )
        if isinstance(value, Mapping):
            stack.extend((item, depth + 1) for item in value.values())
        elif isinstance(value, list):
            stack.extend((item, depth + 1) for item in value)
    return parsed


def serialize_json_document(value: Any, *, pretty: bool = False) -> str:
    """Serialize strict UTF-8 JSON and fail if any NaN/Infinity escaped checks."""

    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        indent=2 if pretty else None,
        separators=None if pretty else (",", ":"),
        sort_keys=pretty,
    )


# ---------------------------------------------------------------------------
# Request-envelope and record adapter
# ---------------------------------------------------------------------------

def parse_prediction_request(payload: Any) -> ParsedPredictionRequest:
    """Validate a v1 request and map public snake_case fields to model columns.

    Envelope failures raise :class:`RequestContractError`.  Record-level field
    failures are retained so a valid batch can return a correlated result for
    every record without scoring invalid rows.
    """

    if not isinstance(payload, Mapping):
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_request_type",
                    None,
                    "Prediction request must be a JSON object",
                )
            ]
        )

    required_envelope = {"schema_version", "request_id", "records"}
    unknown_envelope = sorted(set(payload).difference(required_envelope))
    missing_envelope = sorted(required_envelope.difference(payload))
    envelope_errors = [
        contract_issue("unknown_field", field, f"Unknown request field: {field}")
        for field in unknown_envelope
    ]
    envelope_errors.extend(
        contract_issue("missing_field", field, f"Missing request field: {field}")
        for field in missing_envelope
    )
    if envelope_errors:
        raise RequestContractError(envelope_errors)

    if payload["schema_version"] != REQUEST_SCHEMA_VERSION:
        raise RequestContractError(
            [
                contract_issue(
                    "unsupported_schema_version",
                    "schema_version",
                    f"schema_version must be {REQUEST_SCHEMA_VERSION}",
                )
            ]
        )

    request_id = payload["request_id"]
    if not _valid_identifier(request_id):
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_identifier",
                    "request_id",
                    "request_id must start with an ASCII letter or digit and contain "
                    "only letters, digits, '.', '_', ':', or '-' (max 128 characters)",
                )
            ]
        )

    records = payload["records"]
    if isinstance(records, (str, bytes)) or not isinstance(records, Sequence):
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_records_type",
                    "records",
                    "records must be a JSON array",
                )
            ]
        )
    if not 1 <= len(records) <= MAX_BATCH_SIZE:
        raise RequestContractError(
            [
                contract_issue(
                    "invalid_batch_size",
                    "records",
                    f"records must contain between 1 and {MAX_BATCH_SIZE} items",
                )
            ]
        )

    record_ids: list[str] = []
    model_rows: list[dict[str, Any]] = []
    all_record_errors: list[tuple[dict[str, Any], ...]] = []

    for index, record in enumerate(records):
        if not isinstance(record, Mapping):
            raise RequestContractError(
                [
                    contract_issue(
                        "invalid_record_type",
                        f"records[{index}]",
                        "Every records item must be a JSON object",
                    )
                ]
            )
        record_id = record.get("record_id")
        if not _valid_identifier(record_id):
            raise RequestContractError(
                [
                    contract_issue(
                        "invalid_identifier",
                        f"records[{index}].record_id",
                        "record_id must start with an ASCII letter or digit and contain "
                        "only letters, digits, '.', '_', ':', or '-' (max 128 characters)",
                    )
                ]
            )
        if record_id in record_ids:
            raise RequestContractError(
                [
                    contract_issue(
                        "duplicate_record_id",
                        f"records[{index}].record_id",
                        f"Duplicate record_id: {record_id}",
                    )
                ]
            )

        row, errors = _parse_record(record)
        record_ids.append(record_id)
        model_rows.append(row)
        all_record_errors.append(tuple(errors))

    return ParsedPredictionRequest(
        request_id=request_id,
        record_ids=tuple(record_ids),
        frame=pd.DataFrame(model_rows),
        record_errors=tuple(all_record_errors),
    )


def _parse_record(
    record: Mapping[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Validate one external record and create its internal model row."""

    errors: list[dict[str, Any]] = []
    unknown = sorted(set(record).difference(RECORD_FIELDS))
    missing = sorted(RECORD_FIELDS.difference(record))
    errors.extend(
        contract_issue("unknown_field", field, f"Unknown field: {field}")
        for field in unknown
    )
    errors.extend(
        contract_issue("missing_field", field, f"Missing field: {field}")
        for field in missing
        if field != "record_id"
    )

    row: dict[str, Any] = {
        "Measured At": _string_value(
            record.get("measured_at"),
            field="measured_at",
            errors=errors,
        ),
    }

    for api_field, model_field in NUMERIC_FIELDS_TO_MODEL.items():
        row[model_field] = _finite_number(
            record.get(api_field),
            field=api_field,
            errors=errors,
        )

    for api_field, model_field in BOOLEAN_FIELDS_TO_MODEL.items():
        value = record.get(api_field)
        if isinstance(value, bool):
            row[model_field] = int(value)
        else:
            if api_field in record:
                errors.append(
                    contract_issue(
                        "invalid_type",
                        api_field,
                        f"{api_field} must be a JSON boolean",
                    )
                )
            row[model_field] = None

    sugar_value, sugar_unit = _measurement_object(
        record.get("blood_sugar"),
        field="blood_sugar",
        allowed_units={"mmol/L", "mg/dL"},
        errors=errors,
    )
    row["BS"] = sugar_value
    row["BS Unit"] = sugar_unit

    temperature_value, temperature_unit = _measurement_object(
        record.get("body_temperature"),
        field="body_temperature",
        allowed_units={"C", "F"},
        errors=errors,
    )
    row["Body Temp"] = temperature_value
    row["Body Temp Unit"] = temperature_unit
    return row, errors


def _measurement_object(
    value: Any,
    *,
    field: str,
    allowed_units: set[str],
    errors: list[dict[str, Any]],
) -> tuple[float | None, str | None]:
    """Parse a strict ``{value, unit}`` measurement object."""

    if not isinstance(value, Mapping):
        if value is not None:
            errors.append(
                contract_issue(
                    "invalid_type",
                    field,
                    f"{field.rsplit('.', 1)[-1]} must be an object with value and unit",
                )
            )
        return None, None

    expected = {"value", "unit"}
    for key in sorted(set(value).difference(expected)):
        errors.append(
            contract_issue("unknown_field", f"{field}.{key}", f"Unknown field: {key}")
        )
    for key in sorted(expected.difference(value)):
        errors.append(
            contract_issue("missing_field", f"{field}.{key}", f"Missing field: {key}")
        )

    numeric_value = _finite_number(
        value.get("value"), field=f"{field}.value", errors=errors
    )
    unit = value.get("unit")
    if not isinstance(unit, str) or unit not in allowed_units:
        if "unit" in value:
            errors.append(
                contract_issue(
                    "invalid_unit",
                    f"{field}.unit",
                    f"unit must be one of: {', '.join(sorted(allowed_units))}",
                )
            )
        unit = None
    return numeric_value, unit


def _finite_number(
    value: Any,
    *,
    field: str,
    errors: list[dict[str, Any]],
) -> float | None:
    """Accept JSON numbers only, explicitly excluding booleans and non-finite values."""

    if isinstance(value, bool) or not isinstance(value, Real):
        if value is not None:
            errors.append(
                contract_issue("invalid_type", field, f"{field.rsplit('.', 1)[-1]} must be a number")
            )
        return None
    try:
        number = float(value)
    except (OverflowError, TypeError, ValueError):
        errors.append(
            contract_issue("non_finite_number", field, "Number must be finite")
        )
        return None
    if not math.isfinite(number):
        errors.append(
            contract_issue("non_finite_number", field, "Number must be finite")
        )
        return None
    return number


def _string_value(
    value: Any,
    *,
    field: str,
    errors: list[dict[str, Any]],
) -> str | None:
    """Accept a non-empty JSON string without coercion."""

    if isinstance(value, str) and value:
        return value
    if value is not None:
        errors.append(
            contract_issue("invalid_type", field, f"{field.rsplit('.', 1)[-1]} must be a string")
        )
    return None


def _valid_identifier(value: Any) -> bool:
    return isinstance(value, str) and IDENTIFIER_PATTERN.fullmatch(value) is not None
