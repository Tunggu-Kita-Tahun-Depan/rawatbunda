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


class PersistenceError(RuntimeError):
    """A durable write failed; callers must not claim that scoring was stored."""


class RequestIdConflict(PersistenceError):
    """A request_id was reused for a different patient, encounter, or input."""


class EncounterCorrelationError(PersistenceError):
    """The encounter does not belong to the supplied patient and episode."""


class PatientAccessDenied(PersistenceError):
    """The authenticated bidan is not assigned to the supplied patient."""


class PredictionStore(Protocol):
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


class InMemoryPredictionStore:
    """Deterministic local/test store that mirrors request-id idempotency."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._jobs: dict[str, dict[str, Any]] = {}

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


__all__ = [
    "InMemoryPredictionStore",
    "JobClaim",
    "PersistenceError",
    "PredictionStore",
    "RequestIdConflict",
    "StoredPrediction",
    "SupabasePredictionStore",
]
