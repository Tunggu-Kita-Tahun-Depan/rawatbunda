# RawatBunda — Team Work Plan (Hackathon)

Based on `RAWATBUNDA_PRD_V2.md` v2.2 (patient-first workflow, three roles, view-only pasien).

Team: 4 people — Person A and Person B build the app (frontend + backend), Person C and Person D build the ML model.

Rule of thumb: the app must demo end-to-end **without** ML and **without** live AI documentation. Those two plug in at the end as clearly-labeled enhancements.

---

## Person A — Bidan clinical spine

The deepest journey in the PRD: select patient → enter encounter → get recommendation → worklist.

1. **Core data models**: `Patient`, `PregnancyEpisode`, `Encounter`, `Observation` (with unit, timestamps, source, verification status), `ClinicalTask`, `PriorityAssessment` (band + reasons + rule version).
2. **`PatientRepository` interface + `InMemoryPatientRepository`**: 30 synthetic patients; one with 4 dated visits and a worsening BP trend; one emergency scenario.
3. **Pasien tab (patient directory)**: search, select patient, `Tambah pasien` with required fields and duplicate warning.
4. **Record-encounter screen**: structured measurements with units, symptoms, validation (plausibility, missing fields).
5. **Deterministic recommendation engine**: safety floor from `clinical_rules.dart` + band logic + 2–4 reason chips; result screen with bidan confirm / raise / override (with reason).
6. **Beranda → `Prioritas Hari Ini`**: worklist built from saved, confirmed recommendations.
7. **Patient overview + four-visit trend** (BP & weight chart).

Owns: `lib/features/patients/`, `lib/features/encounter/`, recommendation engine, Beranda.

## Person B — Roles, referral rework, documentation

1. **Role routing**: `app_role` (`bidan | pasien | admin`) on the user (Supabase user metadata or a `profiles` table) + go_router redirect per role. **Person B owns the router and `AppAuthState` this round.**
2. **Pasien view-only screens**: Beranda (appointments/reminders), Monitoring (schedule, read-only), Profil. **Minimal Admin view**: synthetic facility configuration list.
3. **Referral rework** (existing flow): bidan-recorded external response — accept/decline with mandatory reason, contact name, channel, source; reroute without re-entry; relabel the existing receiving screen as the *simulated* response tool.
4. **Documentation module**: typed narrative → template-based SOAP draft → `Draf → Perlu diperiksa → Disahkan` states → clinical handoff preview + family-instruction preview. (Live Gemini/STT via Supabase Edge Function is a **stretch goal**, only after the typed path works end-to-end.)

Owns: router/auth, `lib/features/referral/`, `lib/features/documentation/`, pasien + admin screens.

## Persons C & D — Machine learning

Constraints from the PRD (§2 Recommendation contract, §8.5): the model proposes a **workflow priority band**, never a diagnosis; it can never lower the safety floor; it is labeled synthetic/experimental in the demo.

1. **Agree the contract with Person A on day one** (this is the whole integration):
   - Input JSON: patient/pregnancy context, current encounter values, history features, missingness indicators, timestamps.
   - Output JSON: `proposed_band`, `contributing_factors[]`, `missing_inputs[]`, `generated_at`, `model_version`.
2. Train/evaluate against synthetic data; deliver either a small HTTP endpoint (Supabase Edge Function) or a lookup/heuristic the app can call.
3. The app integrates through an `MlRecommendationService` interface. Person A ships a `FakeMlRecommendationService` first, so the app never blocks on ML. Swapping in the real one is the last step.
4. Prepare the honest pitch slide: what the model does, what data it was trained on, why it is *not* clinically validated, and what validation would be required (PRD §8.5, §20).

## Integration points (where you must talk to each other)

| Interface | Between | Contract |
|---|---|---|
| Route names + role redirects | A ↔ B | B owns router; A hands B route names for new screens |
| Confirmed encounter → referral case | A ↔ B | B's referral flow reads A's confirmed encounter data (no retyping) |
| `MlRecommendationService` | A ↔ C/D | JSON contract above; fake implementation until the real one lands |
| Signed SOAP → handoff document | A ↔ B | B's handoff pulls only bidan-confirmed fields |

## Suggested sequence (checkpoint at the halfway mark)

- **First half**: A finishes items 1–5; B finishes items 1–3. Checkpoint: login as each role → pick patient → enter encounter → rules-only recommendation → worklist → referral with recorded external response. That is already a complete, honest demo.
- **Second half**: A finishes 6–7; B does documentation (typed path). Then stretch goals in this order: ML integration → Gemini audio → polish.

## Git workflow

- Everyone branches off `feat/prd-v2-pivot`: e.g. `feat/patient-spine` (A), `feat/roles-referral` (B), `feat/ml-service` (C/D).
- Small commits, push at least daily, merge via GitHub pull requests — never two people pushing to the same branch.
- Before every merge: `flutter analyze && flutter test` must pass.
- Demo safety net: in-memory mode (no Supabase) must always keep working; tests use `RawatBundaApp(useSupabase: false)`.
