"""Strict contracts for patient creation and bidan-confirmed assessments."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Mapping
from uuid import UUID

from .backend_contracts import (
    BACKEND_SCHEMA_VERSION,
    EvaluationRequest,
    MODEL_INPUT_FIELDS,
    parse_evaluation_request,
)
from .contracts import RequestContractError, contract_issue


CONFIRMATION_FIELDS = {
    "schema_version",
    "request_id",
    "patient_id",
    "pregnancy_episode_id",
    "encounter_id",
    "stt_draft_id",
    "bidan_confirmed",
    "model_input",
    "clinical_context",
    "soap_note",
}
CLINICAL_CONTEXT_FIELDS = {
    "weight_kg",
    "height_cm",
    "severe_headache",
    "visual_disturbance",
    "urine_protein",
    "notes",
}
SOAP_FIELDS = {"subjective", "objective", "assessment", "plan"}
PATIENT_CREATE_FIELDS = {
    "schema_version",
    "display_name",
    "age_years",
    "gestational_age_weeks",
    "gravida",
    "para",
    "abortus",
}


@dataclass(frozen=True)
class PriorityDraft:
    final_band: str
    needs_verification: bool
    reasons: tuple[str, ...]
    missing_inputs: tuple[str, ...]
    generated_at: str


@dataclass(frozen=True)
class ConfirmationRequest:
    evaluation: EvaluationRequest
    stt_draft_id: str | None
    clinical_context: dict[str, Any]
    soap_note: dict[str, str]
    priority: PriorityDraft


@dataclass(frozen=True)
class PatientCreateRequest:
    display_name: str
    age_years: int
    gestational_age_weeks: int
    gravida: int
    para: int
    abortus: int


def _strict_fields(payload: Mapping[str, Any], expected: set[str]) -> list[dict[str, Any]]:
    errors = [
        contract_issue("unknown_field", field, f"Unknown field: {field}")
        for field in sorted(set(payload).difference(expected))
    ]
    errors.extend(
        contract_issue("missing_field", field, f"Missing field: {field}")
        for field in sorted(expected.difference(payload))
    )
    return errors


def _uuid_or_none(value: Any, *, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise RequestContractError(
            [contract_issue("invalid_identifier", field, f"{field} must be a UUID or null")]
        )
    try:
        return str(UUID(value))
    except (ValueError, AttributeError) as error:
        raise RequestContractError(
            [contract_issue("invalid_identifier", field, f"{field} must be a UUID or null")]
        ) from error


def _parse_clinical_context(value: Any) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise RequestContractError(
            [contract_issue("invalid_type", "clinical_context", "clinical_context must be an object")]
        )
    unknown = sorted(set(value).difference(CLINICAL_CONTEXT_FIELDS))
    errors = [
        contract_issue(
            "unknown_field",
            f"clinical_context.{field}",
            f"Unknown clinical context field: {field}",
        )
        for field in unknown
    ]
    parsed: dict[str, Any] = {}
    for field in ("weight_kg", "height_cm"):
        item = value.get(field)
        if item is None:
            continue
        if isinstance(item, bool) or not isinstance(item, (int, float)) or item <= 0:
            errors.append(
                contract_issue(
                    "invalid_value",
                    f"clinical_context.{field}",
                    f"{field} must be a positive number",
                )
            )
        else:
            parsed[field] = float(item)
    for field in ("severe_headache", "visual_disturbance"):
        item = value.get(field, False)
        if not isinstance(item, bool):
            errors.append(
                contract_issue(
                    "invalid_type",
                    f"clinical_context.{field}",
                    f"{field} must be boolean",
                )
            )
        else:
            parsed[field] = item
    urine = value.get("urine_protein", "not_tested")
    if urine not in {"not_tested", "negative", "trace", "positive"}:
        errors.append(
            contract_issue(
                "invalid_value",
                "clinical_context.urine_protein",
                "urine_protein must be not_tested, negative, trace, or positive",
            )
        )
    else:
        parsed["urine_protein"] = urine
    notes = value.get("notes", "")
    if not isinstance(notes, str) or len(notes) > 10_000:
        errors.append(
            contract_issue(
                "invalid_value",
                "clinical_context.notes",
                "notes must be a string of at most 10000 characters",
            )
        )
    else:
        parsed["notes"] = notes.strip()
    if errors:
        raise RequestContractError(errors)
    return parsed


def _parse_soap_note(value: Any) -> dict[str, str]:
    if not isinstance(value, Mapping):
        raise RequestContractError(
            [contract_issue("invalid_type", "soap_note", "soap_note must be an object")]
        )
    unknown = sorted(set(value).difference(SOAP_FIELDS))
    errors = [
        contract_issue("unknown_field", f"soap_note.{field}", f"Unknown SOAP field: {field}")
        for field in unknown
    ]
    parsed: dict[str, str] = {}
    for field in SOAP_FIELDS:
        item = value.get(field, "")
        if not isinstance(item, str) or len(item) > 10_000:
            errors.append(
                contract_issue(
                    "invalid_value",
                    f"soap_note.{field}",
                    f"{field} must be a string of at most 10000 characters",
                )
            )
        else:
            parsed[field] = item.strip()
    if errors:
        raise RequestContractError(errors)
    return parsed


def _priority_from_confirmation(
    model_input: Mapping[str, Any], clinical_context: Mapping[str, Any]
) -> PriorityDraft:
    missing = tuple(sorted(MODEL_INPUT_FIELDS.difference(model_input)))
    reasons: list[str] = []
    band = "rutin"
    sys = model_input.get("systolic_bp_mmhg")
    dia = model_input.get("diastolic_bp_mmhg")
    sys_value = float(sys) if isinstance(sys, (int, float)) and not isinstance(sys, bool) else None
    dia_value = float(dia) if isinstance(dia, (int, float)) and not isinstance(dia, bool) else None
    danger = bool(clinical_context.get("severe_headache")) or bool(
        clinical_context.get("visual_disturbance")
    )
    if sys_value is None or dia_value is None:
        reasons.append("Tekanan darah belum lengkap - perlu diverifikasi")
    if ((sys_value or 0) >= 160 or (dia_value or 0) >= 110) and danger:
        band = "darurat"
        reasons.append("Tekanan darah pada ambang berat disertai gejala bahaya")
    elif (sys_value or 0) >= 160 or (dia_value or 0) >= 110:
        band = "prioritas"
        reasons.append("Tekanan darah pada ambang berat - ulangi pengukuran sesi ini")
    elif danger:
        band = "prioritas"
        reasons.append("Gejala bahaya dilaporkan - periksa pada sesi ini")
    elif (sys_value or 0) >= 140 or (dia_value or 0) >= 90:
        band = "prioritas"
        reasons.append("Tekanan darah meningkat - tinjau lebih awal")
    if clinical_context.get("urine_protein") == "positive" and band != "darurat":
        band = "prioritas"
        reasons.append("Protein urin positif pada kunjungan terakhir")
    return PriorityDraft(
        final_band=band,
        needs_verification=bool(missing),
        reasons=tuple(reasons[:4]),
        missing_inputs=missing,
        generated_at=datetime.now(timezone.utc).isoformat(),
    )


def parse_confirmation_request(payload: Any) -> ConfirmationRequest:
    if not isinstance(payload, Mapping):
        raise RequestContractError(
            [contract_issue("invalid_request_type", None, "Confirmation request must be an object")]
        )
    errors = _strict_fields(payload, CONFIRMATION_FIELDS)
    if errors:
        raise RequestContractError(errors)
    if payload["bidan_confirmed"] is not True:
        raise RequestContractError(
            [
                contract_issue(
                    "confirmation_required",
                    "bidan_confirmed",
                    "bidan_confirmed must be true after manual review",
                )
            ]
        )
    evaluation = parse_evaluation_request(
        {key: payload[key] for key in (
            "schema_version",
            "request_id",
            "patient_id",
            "pregnancy_episode_id",
            "encounter_id",
            "model_input",
        )}
    )
    stt_draft_id = _uuid_or_none(payload["stt_draft_id"], field="stt_draft_id")
    clinical_context = _parse_clinical_context(payload["clinical_context"])
    soap_note = _parse_soap_note(payload["soap_note"])
    return ConfirmationRequest(
        evaluation=evaluation,
        stt_draft_id=stt_draft_id,
        clinical_context=clinical_context,
        soap_note=soap_note,
        priority=_priority_from_confirmation(payload["model_input"], clinical_context),
    )


def parse_patient_create_request(payload: Any) -> PatientCreateRequest:
    if not isinstance(payload, Mapping):
        raise RequestContractError(
            [contract_issue("invalid_request_type", None, "Patient request must be an object")]
        )
    errors = _strict_fields(payload, PATIENT_CREATE_FIELDS)
    if errors:
        raise RequestContractError(errors)
    if payload["schema_version"] != BACKEND_SCHEMA_VERSION:
        raise RequestContractError(
            [contract_issue("unsupported_schema_version", "schema_version", "schema_version must be 1.0")]
        )
    name = payload["display_name"]
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 200:
        errors.append(contract_issue("invalid_value", "display_name", "display_name is required"))
    ranges = {
        "age_years": (12, 60),
        "gestational_age_weeks": (1, 43),
        "gravida": (0, 15),
        "para": (0, 15),
        "abortus": (0, 15),
    }
    values: dict[str, int] = {}
    for field, (minimum, maximum) in ranges.items():
        value = payload[field]
        if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
            errors.append(
                contract_issue(
                    "invalid_value",
                    field,
                    f"{field} must be an integer between {minimum} and {maximum}",
                )
            )
        else:
            values[field] = value
    if errors:
        raise RequestContractError(errors)
    return PatientCreateRequest(display_name=name.strip(), **values)


__all__ = [
    "ConfirmationRequest",
    "PatientCreateRequest",
    "PriorityDraft",
    "parse_confirmation_request",
    "parse_patient_create_request",
]
