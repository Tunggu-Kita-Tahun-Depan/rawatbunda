# IbuRujuk (Flutter)

Offline-first maternal emergency referral coordinator — hackathon build.
See `IBURUJUK_PRD.md` for the full product vision. The demo scope is the
4-screen referral click-through (intake → facility match → receiving facility → timeline).

**All patient and facility data is synthetic/simulated.** This app is decision
support, not diagnosis, and is not approved for clinical use.

## Run it

```sh
flutter pub get
flutter run            # pick a device, or:
flutter run -d web-server --web-port 8080   # then open http://localhost:8080
```

Tests and lint:

```sh
flutter analyze
flutter test
```

## Project structure

```
lib/
├── main.dart                 # entry point
├── app.dart                  # MaterialApp + providers
├── core/
│   ├── constants/            # clinical_rules.dart — safety-flag thresholds (FR-006)
│   ├── router/               # app_router.dart — go_router routes; auth guard goes here later
│   └── theme/                # app_theme.dart — change seed color here to restyle
├── data/                     # synthetic_data.dart — demo facilities; replaced by a backend later
├── models/                   # facility.dart, referral.dart — plain data classes
├── state/                    # referral_state.dart — in-memory app state (Provider)
├── features/                 # one folder per screen/role
│   ├── shell/                # app shell with step navigation
│   ├── intake/               # Screen 1 — bidan intake form + safety flag
│   ├── facility_match/       # Screen 2 — facility list, sort/filter
│   ├── receiving/            # Screen 3 — referral summary, accept/decline
│   ├── timeline/             # Screen 4 — status timeline
│   ├── auth/                 # STUB — login placeholder (FR-001, planned)
│   └── dashboard/            # STUB — operations dashboard (FR-021, future)
└── shared/widgets/           # reusable widgets (safety flag banner, ...)
```

## Where future pieces plug in

- **Authentication (FR-001):** implement in `features/auth/`, then add a
  `redirect` guard in `core/router/app_router.dart`.
- **Backend / database:** add a `repositories/` layer; `ReferralState` keeps
  its current API but delegates to repositories instead of mutating in memory.
- **New screens:** new folder under `features/`, register the route in
  `core/router/app_router.dart`.
- **Safety-rule changes:** only touch `core/constants/clinical_rules.dart`.
