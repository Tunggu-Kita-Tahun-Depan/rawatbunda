# RawatBunda

RawatBunda is an integrated maternal health decision support and referral platform for midwives. It helps healthcare workers document examinations, review patient history, identify cases that require attention, and coordinate referrals more efficiently.

The platform combines Flutter, Supabase, speech to text, and a protected machine learning backend. Automated results are treated as clinical support only. A midwife must review and confirm the extracted information before it becomes a confirmed encounter or affects the operational patient worklist.

> RawatBunda is currently a hackathon prototype. The included patient records, facilities, measurements, and referral responses are synthetic or simulated. The system is not a diagnostic tool and has not been approved for clinical use.

## What It Does

RawatBunda supports the maternal care journey from examination to referral while keeping healthcare professionals in control of every important decision.

### 1. AI Assisted Clinical Documentation

The application can record a clinical conversation and send the audio to the protected backend. Speech to text processing produces a transcript, structured health fields, warnings, and a draft SOAP note. The original audio is not retained by the application backend.

### 2. Midwife Reviewed Clinical Records

Extracted measurements and SOAP content remain editable drafts. The midwife must verify the values, units, symptoms, and clinical context before confirming the encounter. Unreviewed drafts never become confirmed patient records.

### 3. Maternal Risk Classification and Safe Prioritization

Confirmed clinical data is processed by the maternal risk model and validated before persistence. The current model operates in experimental shadow mode. Its result is stored for traceability, while governed deterministic safety rules create the operational priority snapshot used by the application.

### 4. Capability Based Referral Coordination

For patients who need referral, the application helps the midwife review eligible facilities based on availability and required capabilities. Facility responses obtained through external communication can be recorded with their source, timestamp, contact information, and decline reason.

### 5. Real Time Patient and Referral Monitoring

Confirmed patients, encounters, predictions, priorities, and referral updates are stored in Supabase. Authorized Flutter clients read the database and refresh their worklists when relevant records change, providing a consistent source of truth across devices.

## Clinical Workflow

```text
Clinical conversation or manual data entry
  -> Protected speech to text draft
  -> Structured fields and SOAP draft
  -> Midwife review and correction
  -> Confirmed assessment
  -> Validated machine learning inference
  -> Deterministic operational priority
  -> Supabase persistence
  -> Flutter patient worklist and referral flow
```

Incomplete model inputs do not silently become zero values. They produce an invalid input result with no model score. Model failures also cannot lower the deterministic safety priority or block an urgent referral workflow.

## Roles and Access

### Bidan

The bidan role can manage assigned patients, add pregnancy episodes and encounters, review speech to text drafts, confirm clinical information, view patient priority, prepare SOAP documentation, select referral facilities, record externally obtained responses, and follow the referral timeline.

### Pasien

The pasien role provides a read only view of the patient's summary, monitoring history, schedule, and profile. Patients cannot edit clinical records, priorities, SOAP notes, facilities, or referral status.

### Admin

The admin role can view facility reference information and account details. It does not receive clinical decision permissions and cannot confirm SOAP notes, classify patients, or choose referrals.

Application routes are guarded by role. Trusted roles come from Supabase `app_metadata`, not user editable profile metadata.

## Architecture

```text
Flutter application
  -> Role aware screens and navigation
  -> Provider state layer
  -> Repository interfaces
     -> Supabase repositories for authenticated data and realtime updates
     -> In memory repositories for local demonstration mode
  -> ClinicalBackendClient
     -> Protected Python backend
        -> Supabase token and bidan role verification
        -> Patient assignment validation
        -> Speech to text draft extraction
        -> Strict request and response validation
        -> Machine learning inference
        -> Service role database functions
  -> Supabase PostgreSQL
     -> Row Level Security
     -> Longitudinal patient records
     -> Prediction and priority history
     -> Realtime change publication
```

The Supabase service role key is used only by the Python backend. It must never be placed in Flutter, browser code, a mobile build, or a committed environment file.

## Technology Stack

### Application

Flutter, Dart, Provider, GoRouter, Supabase Flutter, HTTP, Record, and UUID.

### Backend and Machine Learning

Python, FastAPI, Uvicorn, scikit learn, pandas, NumPy, joblib, JSON Schema, Groq speech to text, and strict typed contracts.

### Data Platform

Supabase Authentication, PostgreSQL, Row Level Security, database functions, and realtime subscriptions.

## Project Structure

```text
lib/core/                         configuration, routing, theme, and safety rules
lib/features/                     role based application screens
lib/models/                       patient, referral, facility, and document models
lib/repositories/                 Supabase and in memory data boundaries
lib/services/                     protected backend client and ML contracts
lib/state/                        authentication and workflow state
ML-Classification/               protected backend and maternal risk model
ML-Classification/artifacts/     versioned model artifact and manifest
ML-Classification/schemas/       JSON request and response contracts
ML-Classification/tests/         backend integration tests
supabase/migrations/              database schema, policies, functions, and views
test/                             Flutter widget and workflow tests
```

## Database Setup

Apply the Supabase migrations in this order:

1. `supabase/migrations/001_init.sql`
2. `supabase/migrations/002_ml_backend.sql`
3. `supabase/migrations/003_clinical_workflow.sql`

The migrations create the referral foundation, longitudinal patient tables, assigned bidan access, speech to text drafts, confirmed encounters, machine learning jobs and predictions, operational priority snapshots, security policies, database functions, views, and realtime publication.

Create users through Supabase Authentication and assign a trusted application role through `app_metadata`. For example:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"app_role":"bidan"}'::jsonb
where email = 'bidan@example.com';
```

Sign out and sign in again after changing the role so the new access token contains the updated metadata.

## Backend Setup

The protected backend requires Python 3.14 and the dependencies declared inside `ML-Classification/requirements.txt`.

Install the backend package:

```powershell
cd ML-Classification
python -m pip install -e .
```

Configure these values in the backend process environment:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
IBURUJUK_MODEL_SHA256
GROQ_API_KEY
CORS_ALLOWED_ORIGINS
```

`GROQ_API_KEY` is required for speech to text. `CORS_ALLOWED_ORIGINS` is optional for localhost development and can contain a comma separated list of additional trusted web origins.

Start the backend:

```powershell
cd ML-Classification
python serve_backend.py --host 0.0.0.0 --port 8081
```

The backend exposes the following application endpoints:

1. `GET /health/live`
2. `GET /health/ready`
3. `POST /v1/patients`
4. `POST /v1/stt/drafts`
5. `POST /v1/assessments/evaluate`
6. `POST /v1/assessments/confirm`

The internal model endpoint is separate from the protected application workflow. Flutter must use the protected backend endpoints and must not call the internal prediction endpoint directly.

## Flutter Setup

Install Flutter dependencies:

```powershell
flutter pub get
```

### Flutter Web

For local web development, the application derives the backend URL from the browser host and uses port `8081`.

```powershell
flutter run -d chrome
```

Localhost browser origins are accepted by the backend. Restart the backend after changing its CORS configuration.

### Android Emulator

The Android emulator automatically uses `http://10.0.2.2:8081` to reach the backend running on the development computer.

```powershell
flutter run -d <emulator-id>
```

### Physical Android Device

The phone and development computer must use the same network. Start the backend with host `0.0.0.0`, then provide the computer's current LAN address:

```powershell
flutter run -d <device-id> --dart-define=BACKEND_URL=http://<computer-ip>:8081
```

Before starting Flutter, open `http://<computer-ip>:8081/health/ready` from the phone browser. A successful JSON response confirms that the phone can reach the backend. Windows Firewall must allow inbound access to port `8081`.

## In Memory Demo Mode

The application includes an in memory fallback for demonstrations without Supabase login or backend access. Clear both public Supabase build values and choose one role:

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY= --dart-define=DEMO_ROLE=bidan
```

Supported demo roles are `bidan`, `pasien`, and `admin`. In memory data resets when the application restarts and does not synchronize across devices.

## Current Prototype Boundaries

1. The maternal risk classifier is experimental and is not authorized to diagnose a patient or directly choose operational urgency.
2. Referral facility responses are entered by the bidan after phone, WhatsApp, or other external communication. There is currently no receiving hospital account.
3. The separate document preview workflow and pasien portal sample content still use in memory repositories.
4. Production offline synchronization, conflict resolution, encrypted local storage, and live facility capacity integration are not implemented yet.
5. Clinical validation, privacy review, audit retention policy, monitoring, and deployment hardening are required before real world use.

## Verification

```powershell
flutter analyze
flutter test
flutter build web --no-pub

cd ML-Classification
python -m unittest discover -s tests -v
```

The backend tests cover authentication, role enforcement, patient assignment, patient creation, speech to text drafts, confirmation requirements, idempotency, incomplete input handling, prediction validation, persistence, and browser CORS behavior.
