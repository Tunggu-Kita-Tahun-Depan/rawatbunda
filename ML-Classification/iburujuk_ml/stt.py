"""Protected speech-to-text and structured clinical draft extraction."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from typing import Any, Mapping, Protocol


MAX_AUDIO_BYTES = 10 * 1024 * 1024
ALLOWED_AUDIO_TYPES = {
    "audio/aac",
    "audio/m4a",
    "audio/mp4",
    "audio/mpeg",
    "audio/ogg",
    "audio/wav",
    "audio/webm",
    "application/octet-stream",
}


class SttServiceError(RuntimeError):
    """External transcription or extraction failed without a safe result."""


@dataclass(frozen=True)
class SttExtraction:
    transcript: str
    model_input: dict[str, Any]
    clinical_context: dict[str, Any]
    soap_note: dict[str, str]
    warnings: list[str]
    generated_at: str


class SpeechToTextService(Protocol):
    def transcribe_and_extract(
        self,
        *,
        filename: str,
        content_type: str,
        audio: bytes,
    ) -> SttExtraction: ...


class GroqSpeechToTextService:
    """Groq Whisper + JSON-mode Llama adapter configured only from env."""

    def __init__(self, *, api_key: str):
        if not api_key.strip():
            raise ValueError("GROQ_API_KEY is required for STT")
        try:
            from groq import Groq
        except ImportError as error:
            raise ValueError("Install the groq package to enable STT") from error
        self._client = Groq(api_key=api_key)

    @classmethod
    def from_environment(cls) -> "GroqSpeechToTextService":
        return cls(api_key=os.environ.get("GROQ_API_KEY", ""))

    def transcribe_and_extract(
        self,
        *,
        filename: str,
        content_type: str,
        audio: bytes,
    ) -> SttExtraction:
        try:
            transcription = self._client.audio.transcriptions.create(
                file=(filename, audio, content_type),
                model="whisper-large-v3",
                language="id",
                response_format="json",
            )
            transcript = str(transcription.text).strip()
        except Exception as error:
            raise SttServiceError("Audio transcription failed") from error
        if not transcript:
            raise SttServiceError("Audio transcription returned empty text")

        prompt = _extraction_prompt(transcript)
        try:
            completion = self._client.chat.completions.create(
                model="llama-3.1-8b-instant",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.0,
                response_format={"type": "json_object"},
            )
            raw = completion.choices[0].message.content
            extracted = json.loads(str(raw).strip())
        except Exception as error:
            raise SttServiceError("Clinical draft extraction failed") from error
        return normalize_extraction(transcript, extracted)


def _extraction_prompt(transcript: str) -> str:
    transcript_json = json.dumps(transcript, ensure_ascii=False)
    return f"""
Anda mengekstrak DIKTE bidan berbahasa Indonesia menjadi DRAF klinis.
Draf wajib diperiksa bidan dan bukan diagnosis. Balas tepat satu JSON object:
{{
  "model_input": {{
    "measured_at": "RFC3339 atau null",
    "age_years": "number atau null",
    "systolic_bp_mmhg": "number atau null",
    "diastolic_bp_mmhg": "number atau null",
    "blood_sugar": {{"value": "number", "unit": "mg/dL atau mmol/L"}},
    "body_temperature": {{"value": "number", "unit": "C atau F"}},
    "bmi_kg_m2": "number atau null",
    "previous_complications": "boolean atau null",
    "preexisting_diabetes": "boolean atau null",
    "gestational_diabetes": "boolean atau null",
    "mental_health_indicator": "boolean atau null",
    "heart_rate_bpm": "number atau null"
  }},
  "clinical_context": {{
    "weight_kg": "number atau null",
    "height_cm": "number atau null",
    "severe_headache": "boolean atau null",
    "visual_disturbance": "boolean atau null",
    "urine_protein": "not_tested, negative, trace, positive, atau null"
  }},
  "soap_note": {{
    "subjective": "string",
    "objective": "string",
    "assessment": "string tanpa membuat diagnosis baru",
    "plan": "string"
  }}
}}

Aturan:
1. Jangan menebak. Nilai yang tidak disebut harus null, bukan 0/false/normal.
2. Pertahankan negasi dengan teliti. "Tidak" berarti false hanya bila eksplisit.
3. Gunakan C atau F untuk suhu, bukan simbol derajat.
4. SOAP hanya merangkum isi dikte; jangan menambahkan fakta.

DIKTE: {transcript_json}
""".strip()


def _number(value: Any) -> float | int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value


def normalize_extraction(transcript: str, payload: Any) -> SttExtraction:
    if not isinstance(payload, Mapping):
        raise SttServiceError("Extraction did not return a JSON object")
    warnings: list[str] = []
    raw_model = payload.get("model_input")
    raw_clinical = payload.get("clinical_context")
    raw_soap = payload.get("soap_note")
    if not isinstance(raw_model, Mapping):
        raw_model = {}
        warnings.append("model_input tidak ditemukan pada hasil ekstraksi")
    if not isinstance(raw_clinical, Mapping):
        raw_clinical = {}
        warnings.append("clinical_context tidak ditemukan pada hasil ekstraksi")
    if not isinstance(raw_soap, Mapping):
        raw_soap = {}
        warnings.append("soap_note tidak ditemukan pada hasil ekstraksi")

    model_input: dict[str, Any] = {}
    measured_at = raw_model.get("measured_at")
    if isinstance(measured_at, str) and measured_at.strip():
        model_input["measured_at"] = measured_at.strip()
    for field in (
        "age_years",
        "systolic_bp_mmhg",
        "diastolic_bp_mmhg",
        "bmi_kg_m2",
        "heart_rate_bpm",
    ):
        value = _number(raw_model.get(field))
        if value is not None:
            model_input[field] = value
    for field in (
        "previous_complications",
        "preexisting_diabetes",
        "gestational_diabetes",
        "mental_health_indicator",
    ):
        value = raw_model.get(field)
        if isinstance(value, bool):
            model_input[field] = value
    for field, allowed_units in (
        ("blood_sugar", {"mg/dL", "mmol/L"}),
        ("body_temperature", {"C", "F"}),
    ):
        measurement = raw_model.get(field)
        if not isinstance(measurement, Mapping):
            continue
        value = _number(measurement.get("value"))
        unit = measurement.get("unit")
        if field == "body_temperature" and unit in {"°C", "Â°C"}:
            unit = "C"
        if field == "body_temperature" and unit in {"°F", "Â°F"}:
            unit = "F"
        if value is not None and unit in allowed_units:
            model_input[field] = {"value": value, "unit": unit}
        else:
            warnings.append(f"{field} diabaikan karena nilai atau unit tidak valid")

    clinical_context: dict[str, Any] = {}
    for field in ("weight_kg", "height_cm"):
        value = _number(raw_clinical.get(field))
        if value is not None and value > 0:
            clinical_context[field] = value
    for field in ("severe_headache", "visual_disturbance"):
        value = raw_clinical.get(field)
        if isinstance(value, bool):
            clinical_context[field] = value
    urine = raw_clinical.get("urine_protein")
    if urine in {"not_tested", "negative", "trace", "positive"}:
        clinical_context["urine_protein"] = urine

    soap_note = {
        field: str(raw_soap.get(field, "")).strip()
        if isinstance(raw_soap.get(field, ""), str)
        else ""
        for field in ("subjective", "objective", "assessment", "plan")
    }
    expected = {
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
    missing = sorted(expected.difference(model_input))
    if missing:
        warnings.append("Periksa dan lengkapi: " + ", ".join(missing))
    return SttExtraction(
        transcript=transcript,
        model_input=model_input,
        clinical_context=clinical_context,
        soap_note=soap_note,
        warnings=warnings,
        generated_at=datetime.now(timezone.utc).isoformat(),
    )


__all__ = [
    "ALLOWED_AUDIO_TYPES",
    "GroqSpeechToTextService",
    "MAX_AUDIO_BYTES",
    "SpeechToTextService",
    "SttExtraction",
    "SttServiceError",
    "normalize_extraction",
]
