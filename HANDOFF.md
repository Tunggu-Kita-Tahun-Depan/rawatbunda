# RawatBunda — Agent Handoff Brief

_Last updated: 17 July 2026. Update this file when major decisions or milestones change._

## Project context

- **Product:** RawatBunda (renamed from "IbuRujuk" — update any pitch materials that still say IbuRujuk), a maternal emergency referral coordinator built for a 30-hour hackathon.
- **Source of truth for vision:** `IBURUJUK_PRD.md` (repo root). The PRD is reference/pitch material, **not** the build target. Demo scope = the 4-step referral click-through.
- **Team:** low coding experience, relies on AI assistants. Explain changes clearly; don't assume Flutter knowledge. Do not expand scope beyond the demo without asking.
- **Repo:** `github.com/Tunggu-Kita-Tahun-Depan/tunggukitatahundepan2026`, local at `~/Documents/tunggukitatahundepan2026`. Flutter project is at the repo root. An older repo (`leains/TungguKitaTahunDepan2026`) is dead — ignore it.
- **Machine:** macOS, Flutter 3.44.6. **No Chrome installed** (run with `flutter run -d web-server --web-port 8080` and open in Safari). **No Android SDK, no full Xcode** — web is the only buildable target, and that's intentional: the hackathon targets mobile *browser*. Platform folders kept: `web/`, `android/`, `ios/` (the latter two for the future; they can't build on this machine). macos/windows/linux were deleted.

## Current state (all committed, working tree clean)

- **App shell:** three-tab navigation — Beranda (home), Rujukan (the 4-step referral flow), Profil. Referral routes live under `/referral/*` (intake → facility match → receiving → timeline).
- **All UI in Bahasa Indonesia** with a custom design system (`lib/shared/widgets/rawat_bunda_components.dart`, `lib/core/theme/app_theme.dart` — AppTheme exposes named colors like `primary`, `accentLime`, `ink`, `mutedInk`).
- **Safety rule (PRD FR-006):** BP ≥160 systolic OR ≥110 diastolic AND ≥1 danger symptom → warning banner with trigger details, labeled "pendukung keputusan, bukan diagnosis". Logic lives ONLY in `lib/core/constants/clinical_rules.dart`.
- **Timeline:** live elapsed-time counter since referral sent (maps to the PRD's #1 metric: decision-to-acknowledgement time — point at it during the pitch).
- **Supabase backend live:** project "rawatbunda" at `https://fukehrorqwipudihexfq.supabase.co`. Schema already applied from `supabase/migrations/001_init.sql` (tables `facilities` + `referral_cases`, RLS = authenticated-only, realtime publication, 3 seeded synthetic facilities). Login works; demo users created via dashboard (Auto Confirm).
- **Keys are baked into `lib/core/config/env.dart`** as defaults (anon/publishable key — public by design, safe in git; the service_role key must NEVER appear anywhere). Plain `flutter run` = Supabase mode with login. Passing both defines empty (`--dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY=`) = in-memory demo mode: no login, no network. Widget tests use `RawatBundaApp(useSupabase: false)`.
- **Verification:** `flutter analyze` clean, widget tests in `test/widget_test.dart` pass, `flutter build web` succeeds. Always re-run all three after changes.

## Architecture

```
UI (features/*) → ReferralState / AppAuthState (state/, Provider)
                → ReferralRepository / FacilityRepository (repositories/)
                    ├── InMemory…  (default fallback, no backend)
                    └── Supabase…  (PostgreSQL + realtime + auth)
```

- UI never talks to Supabase directly — only through the repositories. Backend swaps/offline queue (FR-018)/FHIR adapter (FR-022) plug in there.
- Realtime: devices stream `referral_cases` changes → multi-device demo (bidan sends on phone A, facility sees it on phone B in ~1s).
- Routing: go_router in `lib/core/router/app_router.dart` with an auth redirect guard.
- See `README.md` for setup/run instructions and `UI_UX_IMPLEMENTATION_PLAN.md` for the UI plan.

## Decisions already made (don't relitigate)

1. Frontend-first. Backend exists and works; deeper backend work (per-role RLS, real datasets) is deferred until the team's dataset decisions land.
2. ⚠️ Teammates are **training an AI model** (purpose not yet stated). The PRD/brief explicitly forbid claiming AI pre-eclampsia diagnosis ("no proprietary risk score in the MVP"; never claim "our AI diagnoses better than a bidan"). If the model is risk-screening, position it as upstream/future input only.
3. Multi-device demo chosen (bidan phone + facility phone) via Supabase realtime.
4. Product name is RawatBunda; Dart package name stays `tunggukitatahundepan2026` (renaming touches every import — not worth it).

## Operational gotchas

- **Supabase free tier pauses after ~1 week idle.** Unpause in the dashboard before demo day.
- Clear the `referral_cases` table (Table Editor → delete rows) before live demos so the flow starts fresh.
- Widget tests crash without `useSupabase: false` (Supabase never initialized in tests).
- The referral stream watches only the **latest** row; `ReferralState.reset()` starts a new local draft and ignores remote updates for old case ids.
- A facility on a referral round-trips by name/distance only — fine for the demo.
- Anonymous REST calls to Supabase returning `[]` is correct (RLS), not a bug.
- Port 8080 sometimes stays held after a dev server dies: `lsof -tiTCP:8080 -sTCP:LISTEN | xargs kill -9`.

## Likely next steps

- Deploy `flutter build web` to a static host (GitHub Pages / Firebase Hosting) so teammates/judges can open it on phones. First load is ~2–3 MB compressed; the PWA service worker caches it after that (good for slow connections).
- Decline-with-reason flow (first facility declines → second accepts) — the PRD's scripted demo beat.
- Pitch deck from PRD §1–3: problem stats, three-delays framing, differentiation table (Teman Ibu / PE-Detector / SEHATI). Record a 2-minute fallback demo video.
- Possible later: per-user roles, mock FHIR `ServiceRequest` preview (generate from `ReferralCase.toRow()`).
