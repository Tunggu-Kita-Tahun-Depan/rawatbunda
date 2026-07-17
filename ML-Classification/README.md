# RawatBunda ML Backend

This folder contains the fail-closed maternal-risk shadow model and the
protected backend boundary that prepares validated predictions for Supabase.
It is not a diagnostic service and the current model is not authorized to set
RawatBunda's operational priority queue.

## Integration boundary

```text
Flutter (future)
  -> POST /v1/assessments/evaluate with Supabase bearer token
  -> backend validates patient/episode access and atomically registers encounter
  -> strict model inference
  -> backend validates the complete model response
  -> service-role-only Supabase RPC
  -> ml_inference_jobs + ml_predictions

Frontend worklist (future)
  <- current_priority_snapshots view
```

The endpoint stores only the raw shadow-model prediction. It deliberately sets
`operational_priority_applied=false` and does not create a confirmed
`priority_snapshot`. A governed priority policy and explicit bidan confirmation
must be implemented before the operational worklist consumes ML.

## Apply database migrations

Run these in order in the Supabase SQL editor:

1. `supabase/migrations/001_init.sql`
2. `supabase/migrations/002_ml_backend.sql`

The second migration creates patient/encounter correlation tables, inference
jobs, raw predictions, future priority snapshots, RLS read policies, realtime
publication, frontend-ready views, and service-role-only atomic RPCs.

Never place `SUPABASE_SERVICE_ROLE_KEY` in Flutter, browser code, a mobile
build, or a checked-in environment file.

## Runtime configuration

Production requires:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
IBURUJUK_MODEL_SHA256
```

`SUPABASE_ANON_KEY` is used only to verify the caller's Supabase access token.
`SUPABASE_SERVICE_ROLE_KEY` is used only by the server to call the protected
database RPCs. `IBURUJUK_MODEL_SHA256` is mandatory in production and must be
pinned from the trusted release manifest rather than discovered next to the
artifact.

Install and run:

```powershell
cd ML-Classification
python -m pip install -e .
python serve_backend.py --host 127.0.0.1 --port 8081
```

For a local synthetic smoke test without Supabase persistence:

```powershell
python serve_backend.py --in-memory --dev-token local-demo-token
```

Then send `examples/synthetic_assessment.json` with:

```text
Content-Type: application/json
Authorization: Bearer local-demo-token
```

## HTTP endpoints

- `GET /health/live`
- `GET /health/ready`
- `POST /v1/assessments/evaluate`

The internal model-only boundary is available separately through
`python -m iburujuk_ml.api` and exposes `POST /v1/predict`. Application clients
must use the protected assessment endpoint, not the internal model endpoint.

## Persistence and idempotency

`request_id` is the idempotency key. Reusing it with the same patient,
pregnancy episode, encounter, model version, and canonical input returns the
stored prediction. Reusing it with different input returns HTTP 409.

The database RPC also verifies that the authenticated bidan has an
`assigned_bidan` row in `patient_access`; knowing patient UUIDs is not enough
to request or read a prediction.

Predictions are attached to `encounter_id`, not merely `patient_id`, so repeat
assessments remain independently auditable. Incomplete inputs are stored as
`invalid_input` with a null score; they are never converted to score zero.
Reusing an `encounter_id` for different clinical input is rejected; a new
measurement must receive a new encounter UUID.

## Safety and frontend contract

- `ml_predictions` is raw experimental evidence and audit data.
- `priority_snapshots` is reserved for the governed rules + optional ML + bidan
  confirmation result.
- The future frontend should read `current_priority_snapshots` for the worklist.
- The current PE classifier may remain visible only as an experimental shadow
  result and must not be renamed into clinical urgency.
- Model or persistence failure must not block emergency rules or referral.
