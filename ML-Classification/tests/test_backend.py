"""End-to-end tests for the protected assessment evaluation boundary."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest

from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator, FormatChecker


ML_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ML_ROOT))

import iburujuk_ml
from iburujuk_ml.auth import StaticTokenVerifier
from iburujuk_ml.backend import create_app
from iburujuk_ml.backend_contracts import parse_evaluation_request
from iburujuk_ml.inference import load_runtime
from iburujuk_ml.persistence import InMemoryPredictionStore, PatientAccessDenied
from iburujuk_ml.response_validation import (
    BackendResponseValidationError,
    validate_prediction_response,
)
from iburujuk_ml.stt import SttExtraction


TOKEN = "backend-test-token"
BIDAN_ID = "00000000-0000-4000-8000-000000000001"


class ProtectedBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        manifest = json.loads(
            (ML_ROOT / "artifacts" / "artifact_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        cls.runtime = load_runtime(
            ML_ROOT / "artifacts" / "maternal_risk_model.joblib",
            expected_sha256=manifest["artifact_sha256"],
        )
        cls.example = json.loads(
            (ML_ROOT / "examples" / "synthetic_assessment.json").read_text(
                encoding="utf-8"
            )
        )
        request_schema = json.loads(
            (ML_ROOT / "schemas" / "assessment_evaluation_request.schema.json").read_text(
                encoding="utf-8"
            )
        )
        cls.request_validator = Draft202012Validator(
            request_schema,
            format_checker=FormatChecker(),
        )

    def setUp(self) -> None:
        self.store = InMemoryPredictionStore()
        self.auth = StaticTokenVerifier(TOKEN, user_id=BIDAN_ID, role="bidan")
        self.application = create_app(
            runtime=self.runtime,
            store=self.store,
            auth_verifier=self.auth,
        )

    def post(self, client: TestClient, payload: dict, *, token: str = TOKEN):
        return client.post(
            "/v1/assessments/evaluate",
            content=json.dumps(payload).encode("utf-8"),
            headers={
                "content-type": "application/json",
                "authorization": f"Bearer {token}",
            },
        )

    def confirm(self, client: TestClient, payload: dict, *, token: str = TOKEN):
        return client.post(
            "/v1/assessments/confirm",
            content=json.dumps(payload).encode("utf-8"),
            headers={
                "content-type": "application/json",
                "authorization": f"Bearer {token}",
            },
        )

    def test_package_is_loaded_from_this_checkout(self) -> None:
        package_path = Path(iburujuk_ml.__file__).resolve()
        self.assertTrue(package_path.is_relative_to(ML_ROOT))

    def test_local_flutter_web_cors_preflight_is_allowed(self) -> None:
        with TestClient(self.application) as client:
            response = client.options(
                "/v1/patients",
                headers={
                    "origin": "http://localhost:54321",
                    "access-control-request-method": "POST",
                    "access-control-request-headers": "authorization,content-type",
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.headers["access-control-allow-origin"],
            "http://localhost:54321",
        )
        self.assertIn("POST", response.headers["access-control-allow-methods"])

    def test_unconfigured_remote_web_origin_is_rejected(self) -> None:
        with TestClient(self.application) as client:
            response = client.options(
                "/v1/patients",
                headers={
                    "origin": "https://untrusted.example",
                    "access-control-request-method": "POST",
                    "access-control-request-headers": "authorization,content-type",
                },
            )

        self.assertEqual(response.status_code, 400)
        self.assertNotIn("access-control-allow-origin", response.headers)

    def test_example_matches_the_public_request_schema(self) -> None:
        self.request_validator.validate(self.example)

    def test_valid_assessment_is_scored_validated_and_stored(self) -> None:
        with TestClient(self.application) as client:
            ready = client.get("/health/ready")
            response = self.post(client, self.example)

        self.assertEqual(ready.status_code, 200)
        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["status"], "stored")
        self.assertEqual(payload["encounter_id"], self.example["encounter_id"])
        self.assertEqual(payload["prediction"]["status"], "ok")
        self.assertIsInstance(payload["prediction"]["model_score"], float)
        self.assertFalse(payload["prediction"]["ranking_eligible"])
        self.assertFalse(payload["operational_priority_applied"])
        self.assertIsNone(payload["priority_snapshot_id"])

    def test_same_request_id_is_an_idempotent_replay(self) -> None:
        with TestClient(self.application) as client:
            first = self.post(client, self.example)
            second = self.post(client, self.example)

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["prediction_id"], second.json()["prediction_id"])
        self.assertTrue(second.json()["idempotent_replay"])

    def test_incomplete_record_is_stored_as_abstention_not_zero(self) -> None:
        incomplete = copy.deepcopy(self.example)
        del incomplete["model_input"]["heart_rate_bpm"]
        incomplete["request_id"] = "demo-incomplete-001"
        incomplete["encounter_id"] = "30000000-0000-4000-8000-000000000002"
        self.request_validator.validate(incomplete)
        with TestClient(self.application) as client:
            response = self.post(client, incomplete)

        self.assertEqual(response.status_code, 201)
        result = response.json()["prediction"]
        self.assertEqual(result["status"], "invalid_input")
        self.assertIsNone(result["model_score"])
        self.assertTrue(result["errors"])

    def test_request_id_cannot_be_reused_with_different_input(self) -> None:
        changed = copy.deepcopy(self.example)
        changed["model_input"]["heart_rate_bpm"] = 93
        with TestClient(self.application) as client:
            first = self.post(client, self.example)
            conflict = self.post(client, changed)

        self.assertEqual(first.status_code, 201)
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(conflict.json()["errors"][0]["code"], "request_id_conflict")

    def test_input_hash_describes_assessment_not_idempotency_key(self) -> None:
        same_assessment = copy.deepcopy(self.example)
        same_assessment["request_id"] = "different-request-id"

        first = parse_evaluation_request(self.example)
        second = parse_evaluation_request(same_assessment)

        self.assertEqual(first.input_hash, second.input_hash)

    def test_authentication_and_role_are_enforced_before_scoring(self) -> None:
        with TestClient(self.application) as client:
            unauthorized = self.post(client, self.example, token="wrong")
        self.assertEqual(unauthorized.status_code, 401)

        admin_app = create_app(
            runtime=self.runtime,
            store=InMemoryPredictionStore(),
            auth_verifier=StaticTokenVerifier(TOKEN, user_id=BIDAN_ID, role="admin"),
        )
        with TestClient(admin_app) as client:
            forbidden = self.post(client, self.example)
        self.assertEqual(forbidden.status_code, 403)

    def test_patient_assignment_is_enforced_by_the_persistence_boundary(self) -> None:
        class DeniedStore(InMemoryPredictionStore):
            def claim_job(self, *args, **kwargs):
                raise PatientAccessDenied(
                    "Authenticated bidan is not assigned to this patient"
                )

        denied_app = create_app(
            runtime=self.runtime,
            store=DeniedStore(),
            auth_verifier=self.auth,
        )
        with TestClient(denied_app) as client:
            response = self.post(client, self.example)

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["errors"][0]["code"], "patient_access_denied")

    def test_backend_rejects_a_tampered_model_response(self) -> None:
        request_id = self.example["request_id"]
        record_id = self.example["encounter_id"]
        from iburujuk_ml.inference import predict_request

        evaluation = parse_evaluation_request(self.example)
        response = predict_request(self.runtime, evaluation.prediction_request)
        response["results"][0]["ranking_eligible"] = True
        with self.assertRaisesRegex(
            BackendResponseValidationError,
            "may not authorize ranking",
        ):
            validate_prediction_response(
                response,
                runtime=self.runtime,
                request_id=request_id,
                record_id=record_id,
            )

    def test_confirmed_assessment_writes_prediction_and_operational_priority(self) -> None:
        confirmed = {
            **copy.deepcopy(self.example),
            "stt_draft_id": None,
            "bidan_confirmed": True,
            "clinical_context": {
                "weight_kg": 65.0,
                "height_cm": 158.0,
                "severe_headache": True,
                "visual_disturbance": False,
                "urine_protein": "positive",
                "notes": "Diperiksa ulang oleh bidan",
            },
            "soap_note": {
                "subjective": "Sakit kepala berat",
                "objective": "TD 164/112 mmHg",
                "assessment": "Perlu evaluasi segera",
                "plan": "Koordinasi rujukan",
            },
        }
        with TestClient(self.application) as client:
            response = self.confirm(client, confirmed)
            replay = self.confirm(client, confirmed)

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["status"], "stored")
        self.assertEqual(payload["prediction"]["status"], "ok")
        self.assertTrue(payload["operational_priority_applied"])
        self.assertEqual(payload["priority"]["final_band"], "darurat")
        self.assertTrue(payload["database_source_of_truth"])
        self.assertEqual(replay.status_code, 200)
        self.assertTrue(replay.json()["idempotent_replay"])

    def test_manual_bidan_confirmation_is_required(self) -> None:
        confirmed = {
            **copy.deepcopy(self.example),
            "stt_draft_id": None,
            "bidan_confirmed": False,
            "clinical_context": {},
            "soap_note": {},
        }
        with TestClient(self.application) as client:
            response = self.confirm(client, confirmed)
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json()["errors"][0]["code"], "confirmation_required")

    def test_stt_creates_unconfirmed_draft_without_retaining_audio(self) -> None:
        class FakeStt:
            def transcribe_and_extract(self, **kwargs):
                self.audio = kwargs["audio"]
                return SttExtraction(
                    transcript="Tekanan darah seratus enam puluh empat per seratus dua belas",
                    model_input={
                        "systolic_bp_mmhg": 164,
                        "diastolic_bp_mmhg": 112,
                    },
                    clinical_context={"severe_headache": True},
                    soap_note={
                        "subjective": "Sakit kepala",
                        "objective": "TD 164/112",
                        "assessment": "Perlu evaluasi",
                        "plan": "Periksa ulang",
                    },
                    warnings=["Periksa dan lengkapi field lain"],
                    generated_at="2026-07-17T10:00:00+00:00",
                )

        fake = FakeStt()
        app = create_app(
            runtime=self.runtime,
            store=InMemoryPredictionStore(),
            auth_verifier=self.auth,
            stt_service=fake,
        )
        with TestClient(app) as client:
            response = client.post(
                "/v1/stt/drafts",
                params={
                    "patient_id": self.example["patient_id"],
                    "pregnancy_episode_id": self.example["pregnancy_episode_id"],
                },
                content=b"RIFF-test-audio",
                headers={
                    "content-type": "audio/wav",
                    "authorization": f"Bearer {TOKEN}",
                },
            )

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["status"], "pending_bidan_review")
        self.assertTrue(payload["requires_bidan_confirmation"])
        self.assertFalse(payload["audio_retained"])
        self.assertEqual(fake.audio, b"RIFF-test-audio")

    def test_patient_creation_is_a_protected_backend_write(self) -> None:
        request = {
            "schema_version": "1.0",
            "display_name": "Pasien Sintetis",
            "age_years": 28,
            "gestational_age_weeks": 30,
            "gravida": 2,
            "para": 1,
            "abortus": 0,
        }
        with TestClient(self.application) as client:
            response = client.post(
                "/v1/patients",
                content=json.dumps(request).encode("utf-8"),
                headers={
                    "content-type": "application/json",
                    "authorization": f"Bearer {TOKEN}",
                },
            )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["status"], "stored")


if __name__ == "__main__":
    unittest.main()
