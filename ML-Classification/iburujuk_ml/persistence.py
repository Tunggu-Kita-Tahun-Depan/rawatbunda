"""Durable prediction-store boundary with Supabase and in-memory adapters."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from threading import Lock
from typing import Any, Mapping, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

from .backend_contracts import EvaluationRequest
from .clinical_contracts import ConfirmationRequest, PatientCreateRequest
from .stt import SttExtraction


@dataclass(frozen=True)
class JobClaim:
    job_id: str
    status: str
    request_id: str
    claimed: bool
    prediction_id: str | None = None
    stored_response: dict[str, Any] | None = None


@dataclass(frozen=True)
class StoredPrediction:
    job_id: str
    prediction_id: str


@dataclass(frozen=True)
class StoredSttDraft:
    draft_id: str
    created_at: str


@dataclass(frozen=True)
class StoredPriority:
    priority_snapshot_id: str
    final_band: str
    needs_verification: bool
    reasons: list[str]
    missing_inputs: list[str]
    generated_at: str
    idempotent_replay: bool = False


@dataclass(frozen=True)
class CreatedPatient:
    patient_id: str
    pregnancy_episode_id: str


class PersistenceError(RuntimeError):
    """A durable write failed; callers must not claim that scoring was stored."""


class RequestIdConflict(PersistenceError):
    """A request_id was reused for a different patient, encounter, or input."""


class EncounterCorrelationError(PersistenceError):
    """The encounter does not belong to the supplied patient and episode."""


class PatientAccessDenied(PersistenceError):
    """The authenticated bidan is not assigned to the supplied patient."""


class PredictionStore(Protocol):
    def assert_access(
        self,
        *,
        patient_id: str,
        pregnancy_episode_id: str,
        actor_id: str,
    ) -> None: ...

    def create_patient(
        self,
        request: PatientCreateRequest,
        *,
        actor_id: str,
    ) -> CreatedPatient: ...

    def create_stt_draft(
        self,
        *,
        patient_id: str,
        pregnancy_episode_id: str,
        actor_id: str,
        extraction: SttExtraction,
        audio_metadata: Mapping[str, Any],
    ) -> StoredSttDraft: ...

    def claim_job(
        self,
        request: EvaluationRequest,
        *,
        actor_id: str,
        model_version: str,
    ) -> JobClaim: ...

    def complete_job(
        self,
        claim: JobClaim,
        request: EvaluationRequest,
        *,
        actor_id: str,
        model_response: Mapping[str, Any],
    ) -> StoredPrediction: ...

    def fail_job(self, claim: JobClaim, *, code: str, message: str) -> None: ...

    def finalize_assessment(
        self,
        request: ConfirmationRequest,
        *,
        actor_id: str,
        prediction_id: str | None,
    ) -> StoredPriority: ...


class InMemoryPredictionStore:
    """Deterministic local/test store that mirrors request-id idempotency."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._jobs: dict[str, dict[str, Any]] = {}
        self._drafts: dict[str, dict[str, Any]] = {}
        self._priorities: dict[str, StoredPriority] = {}

    def assert_access(
        self,
        *,
        patient_id: str,
        pregnancy_episode_id: str,
        actor_id: str,
    ) -> None:
        return None

    def create_patient(
        self,
        request: PatientCreateRequest,
        *,
        actor_id: str,
    ) -> CreatedPatient:
        return CreatedPatient(str(uuid4()), str(uuid4()))

    def create_stt_draft(
        self,
        *,
        patient_id: str,
        pregnancy_episode_id: str,
        actor_id: str,
        extraction: SttExtraction,
        audio_metadata: Mapping[str, Any],
    ) -> StoredSttDraft:
        draft_id = str(uuid4())
        created_at = extraction.generated_at
        with self._lock:
            self._drafts[draft_id] = {
                "patient_id": patient_id,
                "pregnancy_episode_id": pregnancy_episode_id,
                "actor_id": actor_id,
                "extraction": extraction,
                "audio_metadata": dict(audio_metadata),
            }
        return StoredSttDraft(draft_id=draft_id, created_at=created_at)

    def claim_job(
        self,
        request: EvaluationRequest,
        *,
        actor_id: str,
        model_version: str,
    ) -> JobClaim:
        with self._lock:
            existing = self._jobs.get(request.request_id)
            correlation = (
                request.patient_id,
                request.pregnancy_episode_id,
                request.encounter_id,
                request.input_hash,
                model_version,
            )
            if existing is not None:
                if existing["correlation"] != correlation:
                    raise RequestIdConflict("request_id was reused with different input")
                if existing["status"] == "failed":
                    existing["status"] = "running"
                    existing.pop("error_code", None)
                    existing.pop("error", None)
                    return JobClaim(
                        job_id=existing["job_id"],
                        status="running",
                        request_id=request.request_id,
                        claimed=True,
                    )
                return JobClaim(
                    job_id=existing["job_id"],
                    status=existing["status"],
                    request_id=request.request_id,
                    claimed=False,
                    prediction_id=existing.get("prediction_id"),
                    stored_response=existing.get("response"),
                )
            job_id = str(uuid4())
            self._jobs[request.request_id] = {
                "job_id": job_id,
                "status": "running",
                "correlation": correlation,
                "actor_id": actor_id,
            }
            return JobClaim(
                job_id=job_id,
                status="running",
                request_id=request.request_id,
                claimed=True,
            )

    def complete_job(
        self,
        claim: JobClaim,
        request: EvaluationRequest,
        *,
        actor_id: str,
        model_response: Mapping[str, Any],
    ) -> StoredPrediction:
        with self._lock:
            job = self._jobs[request.request_id]
            prediction_id = job.get("prediction_id") or str(uuid4())
            job.update(
                {
                    "status": "completed",
                    "prediction_id": prediction_id,
                    "response": dict(model_response),
                    "completed_by": actor_id,
                }
            )
            return StoredPrediction(job_id=claim.job_id, prediction_id=prediction_id)

    def fail_job(self, claim: JobClaim, *, code: str, message: str) -> None:
        with self._lock:
            job = self._jobs.get(claim.request_id)
            if job is not None:
                job.update({"status": "failed", "error_code": code, "error": message})

    def finalize_assessment(
        self,
        request: ConfirmationRequest,
        *,
        actor_id: str,
        prediction_id: str | None,
    ) -> StoredPriority:
        with self._lock:
            existing = self._priorities.get(request.evaluation.encounter_id)
            if existing is not None:
                return StoredPriority(
                    **{
                        **existing.__dict__,
                        "idempotent_replay": True,
                    }
                )
            priority = request.priority
            stored = StoredPriority(
                priority_snapshot_id=str(uuid4()),
                final_band=priority.final_band,
                needs_verification=priority.needs_verification,
                reasons=list(priority.reasons),
                missing_inputs=list(priority.missing_inputs),
                generated_at=priority.generated_at,
            )
            self._priorities[request.evaluation.encounter_id] = stored
            return stored


class SupabasePredictionStore:
    """Call service-role-only database RPCs through Supabase PostgREST."""

    def __init__(
        self,
        *,
        supabase_url: str,
        service_role_key: str,
        timeout_seconds: float = 8.0,
    ):
        self._rest_url = f"{supabase_url.rstrip('/')}/rest/v1"
        self._service_role_key = service_role_key
        self._timeout = timeout_seconds

    @classmethod
    def from_environment(cls) -> "SupabasePredictionStore":
        url = os.environ.get("SUPABASE_URL", "").strip()
        service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        if not url or not service_key:
            raise ValueError(
                "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for persistence"
            )
        return cls(supabase_url=url, service_role_key=service_key)

    def _rpc(self, name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        body = json.dumps(
            payload,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
        ).encode("utf-8")
        request = Request(
            f"{self._rest_url}/rpc/{name}",
            data=body,
            method="POST",
            headers={
                "apikey": self._service_role_key,
                "Authorization": f"Bearer {self._service_role_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Cache-Control": "no-store",
            },
        )
        try:
            with urlopen(request, timeout=self._timeout) as response:
                raw = response.read(1_048_577)
        except HTTPError as error:
            try:
                detail = json.loads(error.read(65_536)).get("message", "")
            except (json.JSONDecodeError, AttributeError, UnicodeDecodeError):
                detail = ""
            if "request_id_conflict" in detail:
                raise RequestIdConflict("request_id was reused with different input") from error
            if "encounter_correlation_mismatch" in detail:
                raise EncounterCorrelationError(
                    "encounter_id does not belong to patient_id and pregnancy_episode_id"
                ) from error
            if "pregnancy_episode_correlation_mismatch" in detail:
                raise EncounterCorrelationError(
                    "pregnancy_episode_id does not belong to patient_id"
                ) from error
            if "encounter_input_conflict" in detail:
                raise EncounterCorrelationError(
                    "encounter_id was reused for different assessment input"
                ) from error
            if "patient_access_denied" in detail:
                raise PatientAccessDenied(
                    "Authenticated bidan is not assigned to this patient"
                ) from error
            if "stt_draft" in detail:
                raise EncounterCorrelationError(
                    "STT draft does not belong to this patient encounter"
                ) from error
            if "prediction_encounter_mismatch" in detail:
                raise EncounterCorrelationError(
                    "Prediction does not belong to this encounter"
                ) from error
            raise PersistenceError(f"Supabase RPC {name} failed with HTTP {error.code}") from error
        except (URLError, TimeoutError, OSError) as error:
            raise PersistenceError(f"Supabase RPC {name} is unavailable") from error
        if len(raw) > 1_048_576:
            raise PersistenceError(f"Supabase RPC {name} returned too much data")
        try:
            parsed = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise PersistenceError(f"Supabase RPC {name} returned invalid JSON") from error
        if not isinstance(parsed, dict):
            raise PersistenceError(f"Supabase RPC {name} returned an invalid object")
        return parsed

    def assert_access(
        self,
        *,
        patient_id: str,
        pregnancy_episode_id: str,
        actor_id: str,
    ) -> None:
        self._rpc(
            "assert_bidan_patient_access",
            {
                "p_patient_id": patient_id,
                "p_pregnancy_episode_id": pregnancy_episode_id,
                "p_actor_id": actor_id,
            },
        )

    def create_patient(
        self,
        request: PatientCreateRequest,
        *,
        actor_id: str,
    ) -> CreatedPatient:
        result = self._rpc(
            "create_patient_with_episode",
            {
                "p_created_by": actor_id,
                "p_display_name": request.display_name,
                "p_age_years": request.age_years,
                "p_gestational_age_weeks": request.gestational_age_weeks,
                "p_gravida": request.gravida,
                "p_para": request.para,
                "p_abortus": request.abortus,
            },
        )
        return CreatedPatient(
            patient_id=str(result["patient_id"]),
            pregnancy_episode_id=str(result["pregnancy_episode_id"]),
        )

    def create_stt_draft(
        self,
        *,
        patient_id: str,
        pregnancy_episode_id: str,
        actor_id: str,
        extraction: SttExtraction,
        audio_metadata: Mapping[str, Any],
    ) -> StoredSttDraft:
        result = self._rpc(
            "create_stt_draft",
            {
                "p_patient_id": patient_id,
                "p_pregnancy_episode_id": pregnancy_episode_id,
                "p_created_by": actor_id,
                "p_transcript": extraction.transcript,
                "p_soap_note": extraction.soap_note,
                "p_extracted_model_input": extraction.model_input,
                "p_extracted_clinical_context": extraction.clinical_context,
                "p_extraction_warnings": extraction.warnings,
                "p_audio_metadata": dict(audio_metadata),
            },
        )
        return StoredSttDraft(
            draft_id=str(result["draft_id"]),
            created_at=str(result["created_at"]),
        )

    def claim_job(
        self,
        request: EvaluationRequest,
        *,
        actor_id: str,
        model_version: str,
    ) -> JobClaim:
        result = self._rpc(
            "claim_ml_inference_job",
            {
                "p_request_id": request.request_id,
                "p_patient_id": request.patient_id,
                "p_pregnancy_episode_id": request.pregnancy_episode_id,
                "p_encounter_id": request.encounter_id,
                "p_input_hash": request.input_hash,
                "p_model_version": model_version,
                "p_requested_by": actor_id,
                "p_request_payload": request.request_payload,
            },
        )
        return JobClaim(
            job_id=str(result["job_id"]),
            status=str(result["status"]),
            request_id=str(result["request_id"]),
            claimed=bool(result["claimed"]),
            prediction_id=(
                str(result["prediction_id"])
                if result.get("prediction_id") is not None
                else None
            ),
            stored_response=result.get("model_response"),
        )

    def complete_job(
        self,
        claim: JobClaim,
        request: EvaluationRequest,
        *,
        actor_id: str,
        model_response: Mapping[str, Any],
    ) -> StoredPrediction:
        result = self._rpc(
            "complete_ml_inference_job",
            {
                "p_job_id": claim.job_id,
                "p_completed_by": actor_id,
                "p_model_response": model_response,
            },
        )
        return StoredPrediction(
            job_id=str(result["job_id"]),
            prediction_id=str(result["prediction_id"]),
        )

    def fail_job(self, claim: JobClaim, *, code: str, message: str) -> None:
        self._rpc(
            "fail_ml_inference_job",
            {
                "p_job_id": claim.job_id,
                "p_error_code": code,
                "p_error_message": message[:500],
            },
        )

    def finalize_assessment(
        self,
        request: ConfirmationRequest,
        *,
        actor_id: str,
        prediction_id: str | None,
    ) -> StoredPriority:
        result = self._rpc(
            "confirm_assessment_workflow",
            {
                "p_encounter_id": request.evaluation.encounter_id,
                "p_confirmed_by": actor_id,
                "p_prediction_id": prediction_id,
                "p_stt_draft_id": request.stt_draft_id,
                "p_clinical_context": request.clinical_context,
                "p_soap_note": request.soap_note,
            },
        )
        return StoredPriority(
            priority_snapshot_id=str(result["priority_snapshot_id"]),
            final_band=str(result["final_band"]),
            needs_verification=bool(result["needs_verification"]),
            reasons=[str(value) for value in result.get("reasons", [])],
            missing_inputs=[
                str(value) for value in result.get("missing_inputs", [])
            ],
            generated_at=str(result["generated_at"]),
            idempotent_replay=bool(result.get("idempotent_replay", False)),
        )


__all__ = [
    "InMemoryPredictionStore",
    "CreatedPatient",
    "JobClaim",
    "PersistenceError",
    "PredictionStore",
    "RequestIdConflict",
    "StoredPrediction",
    "StoredPriority",
    "StoredSttDraft",
    "SupabasePredictionStore",
]
