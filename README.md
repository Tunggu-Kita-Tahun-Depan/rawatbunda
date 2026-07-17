# RawatBunda (Flutter)

RawatBunda is an offline-capable maternal-care workflow prototype for midwife. It
helps a midwife review patient data, prioritize follow-up, find the nearest
eligible facility, record an externally obtained referral response, and prepare
reviewed clinical documentation.

The current requirements are in `RAWATBUNDA_PRD_V2rev.md`. The implementation
boundary for this branch is documented in `PERSON_B_IMPLEMENTATION_PLAN.md`.

> All people, measurements, facilities, and referral responses in the demo are
> synthetic or simulated. RawatBunda is decision support, not a diagnosis, and
> is not approved for clinical use.

## Roles and access

There are exactly three application roles. Routes are guarded by role, so a
signed-in user cannot open another role's screens by typing its URL.

| Role | Current access |
| --- | --- |
| **Bidan** | Referral workflow, capable-facility recommendation, response recording, timeline, and reviewed SOAP/document previews |
| **Pasien** | Own summary, monitoring history, schedule, and profile; permanently read-only |
| **Admin** | Facility reference overview and profile; no clinical actions |

There is no receiving-hospital account. A midwife contacts a hospital outside the
app and records the response, channel, source, contact name, time, and decline
reason. Demo responses are clearly labelled as simulated.

## Run locally

The repository contains a public Supabase URL and anon/publishable key as
build-time defaults. A normal run therefore opens the Supabase login flow:

```powershell
flutter pub get
flutter run -d web-server --web-port 8080
```

Open the printed URL in a browser. Never put a Supabase `service_role` key in
Flutter code or in `--dart-define` values.

### In-memory demo mode

Clear both Supabase defines to disable login and network access. `DEMO_ROLE`
accepts `bidan`, `pasien`, or `admin` and defaults to `bidan`.

```powershell
flutter run -d web-server --web-port 8080 --dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY= --dart-define=DEMO_ROLE=bidan
flutter run -d web-server --web-port 8080 --dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY= --dart-define=DEMO_ROLE=pasien
flutter run -d web-server --web-port 8080 --dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY= --dart-define=DEMO_ROLE=admin
```

The in-memory mode is the hackathon safety net. Data resets when the app is
restarted and does not sync between devices.

## Supabase setup

1. Open the Supabase project SQL Editor.
2. Run `supabase/migrations/001_init.sql`. It creates or updates the tables,
   synthetic facilities, realtime publication, and role-based RLS policies.
3. Create and auto-confirm demo users under **Authentication > Users**.
4. Assign each user a trusted server-side `app_metadata.app_role`. For example:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"app_role":"bidan"}'::jsonb
where email = 'bidan@demo.id';
```

Repeat with `pasien` and `admin` for the other demo users. Sign out and sign in
again after changing a role so the access token contains the new metadata. Do
not store access roles in editable `user_metadata`.

The migration intentionally permits referral writes only to `bidan`. Pasien is
read-only at both UI/repository design level in this prototype, while Admin can
maintain facility reference data through RLS but currently receives a read-only
screen.

## Implemented Person B flows

### Bidan referral coordination

1. Enter a synthetic patient assessment.
2. Review the safety flag, which is a transparent rule and not an AI diagnosis.
3. For urgent cases, show only facilities marked available and PONEK-capable,
   then order them by distance.
4. Select a facility and record the response obtained by phone, WhatsApp, or
   another external channel.
5. A decline requires a reason, remains in the attempt history, and returns the
   midwife to the next eligible facility. An acceptance opens the timeline.

### Typed SOAP/document path

The hackathon-safe P0 path works without an LLM: the midwife types a narrative,
confirmed encounter data populates the read-only Objective section, and the
midwife reviews/edits Assessment and Plan before signing. Signing requires human
confirmation. The signed data can produce separate clinical handoff and
minimal family-instruction previews.

Speech-to-text is integrated as a protected draft workflow. Audio is transcribed
and converted into SOAP plus structured fields, but nothing becomes a confirmed
encounter until the bidan reviews the form and explicitly confirms it. The
backend then writes the encounter, validates and stores the ML result, and
creates the deterministic operational priority snapshot read by Flutter.

Backend runtime variables stay on the server only:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
IBURUJUK_MODEL_SHA256
GROQ_API_KEY
CORS_ALLOWED_ORIGINS
```

For local development, Flutter Web derives `BACKEND_URL` from the browser host
and port `8081`, while an Android emulator defaults to
`http://10.0.2.2:8081`. A physical device still needs the development
computer's LAN address, for example
`--dart-define=BACKEND_URL=http://192.168.1.10:8081`. A deployed Web build must
use an HTTPS backend override. Localhost Web origins are accepted by default;
set `CORS_ALLOWED_ORIGINS` to a comma-separated list of additional trusted Web
origins.

## Architecture

```text
UI (features/*)
  -> AppAuthState / ReferralState / DocumentationState
  -> repository interfaces
     -> InMemory implementations (offline demo)
     -> Supabase implementations (auth, PostgreSQL, realtime)
```

The UI does not call Supabase directly. Role resolution uses trusted
`app_metadata`, repository interfaces keep the offline path replaceable, and
clinical safety rules remain centralized in
`lib/core/constants/clinical_rules.dart`.

Key folders:

```text
lib/core/router/             role-aware routes and redirect guards
lib/features/pasien_portal/ view-only patient screens
lib/features/admin/         admin facility overview
lib/features/facility_match capability-first recommendation UI
lib/features/receiving/     bidan-recorded external facility response
lib/features/documentation/ typed narrative, SOAP review, output previews
lib/models/                 roles, referral provenance, documents, portal data
lib/repositories/           in-memory and Supabase boundaries
lib/state/                  authentication, referral, and documentation state
supabase/migrations/         schema, seed data, RLS, realtime setup
```

## Verification

```powershell
flutter analyze
flutter test
flutter build web --no-pub
```

Widget and state tests cover role guards, patient read-only behavior, Admin's
lack of clinical actions, decline/reroute/accept referral history, and SOAP
human-review requirements.

## Deferred to other workstreams

- Person A's full patient directory, add-patient flow, longitudinal encounter
  storage, and ML prioritization integration.
- Production offline queue/conflict resolution and encrypted local storage.
- Live facility capacity or SATUSEHAT integration.
- Gemini/STT extraction, prompt validation, and production document storage.
- Clinical validation, privacy review, audit retention, and deployment hardening.
