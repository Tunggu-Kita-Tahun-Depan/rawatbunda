# RawatBunda (Flutter)

Offline-first maternal emergency referral coordinator — hackathon build.
See `IBURUJUK_PRD.md` for the full product vision. The demo scope is the
4-screen referral click-through (intake → facility match → receiving facility → timeline).

**All patient and facility data is synthetic/simulated.** This app is decision
support, not diagnosis, and is not approved for clinical use.

## Two modes

| Mode | Backend | Login | Multi-device | Setup needed |
|---|---|---|---|---|
| **In-memory** (default) | none | no | no | none — just `flutter run` |
| **Supabase** | PostgreSQL + realtime | yes | yes — referral syncs live across devices | ~10 min, below |

The app picks the mode automatically: if the Supabase keys are provided at
build time it uses Supabase; otherwise everything runs in memory.

## Run it (in-memory mode)

```sh
flutter pub get
flutter run -d chrome        # or: flutter run -d web-server --web-port 8080
```

Tests and lint:

```sh
flutter analyze
flutter test
```

## Supabase setup (multi-device + login)

1. Create a free project at [supabase.com](https://supabase.com) (any name, pick a region near you).
2. In the dashboard: **SQL Editor → New query**, paste the contents of
   `supabase/migrations/001_init.sql`, and **Run**. This creates the tables,
   security policies, realtime publication, and demo facilities.
3. Create demo users: **Authentication → Users → Add user** (e.g.
   `bidan@demo.id` and `rs@demo.id` with a password). Check "Auto Confirm User".
4. Get your keys: **Project Settings → API Keys** — copy the **Project URL**
   and the **publishable** key (`sb_publishable_...`).
5. Run with the keys:

```sh
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co \
  --dart-define=SUPABASE_KEY=sb_publishable_YOURKEY
```

Same flags work for `flutter build web`. To demo multi-device: open the app
on two phones, sign in on both, send a referral from one — it appears on the
other in about a second.

## Architecture

```
UI (features/*) ──> ReferralState / AppAuthState (state/)
                        │
                        ▼
            ReferralRepository, FacilityRepository (repositories/)
              ├── InMemory…   — default, no backend
              └── Supabase…   — PostgreSQL + realtime + auth
                                 schema: supabase/migrations/001_init.sql
```

The UI never talks to Supabase directly — only through the repositories.
That's what makes the two modes interchangeable, and it's where a future
offline queue (PRD FR-018) or FHIR adapter (FR-022) would plug in.

## Project structure

```
lib/
├── main.dart                 # entry point; initializes Supabase if configured
├── app.dart                  # picks repositories by mode, wires providers + router
├── core/
│   ├── config/               # env.dart — reads --dart-define keys
│   ├── constants/            # clinical_rules.dart — safety-flag thresholds (FR-006)
│   ├── router/               # app_router.dart — routes + auth redirect guard
│   └── theme/                # app_theme.dart — change seed color here to restyle
├── data/                     # synthetic_data.dart — demo facilities (in-memory mode)
├── models/                   # facility.dart, referral.dart — data classes + row (de)serialization
├── repositories/             # data access: InMemory* and Supabase* implementations
├── state/                    # referral_state.dart, auth_state.dart (Provider)
├── features/                 # one folder per screen/role
│   ├── shell/                # app shell with step navigation + sign-out
│   ├── intake/               # Screen 1 — bidan intake form + safety flag
│   ├── facility_match/       # Screen 2 — facility list, sort/filter
│   ├── receiving/            # Screen 3 — referral summary, accept/decline
│   ├── timeline/             # Screen 4 — status timeline
│   ├── auth/                 # login screen (Supabase Auth, FR-001)
│   └── dashboard/            # STUB — operations dashboard (FR-021, future)
└── shared/widgets/           # reusable widgets (safety flag banner, ...)
supabase/
└── migrations/001_init.sql   # database schema — paste into Supabase SQL Editor
```

## Where future pieces plug in

- **Roles/permissions (FR-001):** per-role RLS policies in SQL + role field on users.
- **Offline queue (FR-018):** a third `ReferralRepository` implementation that
  wraps Supabase with a local queue.
- **New screens:** new folder under `features/`, register the route in
  `core/router/app_router.dart`.
- **Safety-rule changes:** only touch `core/constants/clinical_rules.dart`.
- **FHIR/SATUSEHAT (FR-022):** mock `ServiceRequest` preview generated from
  `ReferralCase.toRow()` — pitch material, not wired yet.
