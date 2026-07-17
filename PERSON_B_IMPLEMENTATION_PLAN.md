# RawatBunda — Person B Implementation Plan

**Scope owner:** Person B  
**Product decisions:** Bidan is the primary actor; Pasien is permanently view-only; Admin manages configuration; there is no receiving-hospital login.  
**Priority:** Ship an honest end-to-end demo without live ML or Gemini first.  
**Target:** Flutter web/mobile browser with both in-memory and Supabase modes preserved.

---

## 1. Person B outcome

Person B delivers four connected capabilities:

1. Role-aware authentication and navigation for `bidan`, `pasien`, and `admin`.
2. A strictly read-only Pasien experience and minimal read-only Admin facility view.
3. A referral response workflow owned by the bidan, with no receiving-hospital account.
4. Typed, template-based SOAP documentation with review/sign states and separate clinical/family outputs.

Live Gemini or Speech-to-Text is a stretch goal. It must plug into the typed documentation flow rather than becoming a requirement for the demo.

## 2. Scope boundaries

### Person B owns

- `lib/core/router/app_router.dart`
- `lib/state/auth_state.dart`
- role models/profile resolution
- role-specific shells and route guards
- `lib/features/pasien_portal/`
- `lib/features/admin/`
- `lib/features/referral/` or the current referral feature folders being migrated
- `lib/features/documentation/`
- referral/document repositories and Person B tests

### Person A owns

- patient and pregnancy models
- patient directory and `Tambah pasien`
- encounter entry and validation
- deterministic safety floor and recommendation confirmation
- `Prioritas Hari Ini`
- longitudinal trends

### Do not duplicate

Person B must consume Person A's confirmed encounter through an agreed immutable contract. Do not create a second patient or encounter model inside the referral/documentation feature.

## 3. Current repository baseline

The current app already has:

- Supabase login plus in-memory mode.
- `AppAuthState`, but it only knows signed-in versus signed-out.
- one `StatefulShellRoute` with Beranda, Rujukan, and Profil.
- an existing four-step referral prototype.
- repository abstractions for facilities and referrals.
- a receiving-facility screen that automatically acknowledges a referral.
- a timeline and an in-memory/Supabase referral repository.

Important constraints before implementation:

- The working tree already contains substantial uncommitted UI changes. Commit or preserve that baseline before starting Person B work.
- `README.md` references `supabase/migrations/001_init.sql`, but no tracked `supabase/` directory is present in this checkout. Recover or recreate the migration before relying on database role policies.
- `ReferralCase` currently stores mutable patient fields directly and `decline()` erases the selected facility. The new workflow must preserve referral-attempt history.
- The current receiving screen calls `acknowledge()` automatically after rendering. That behavior must be removed because there is no receiving-hospital user.

---

## 4. Architecture decisions

### 4.1 Role source

Use one role per account:

```dart
enum AppRole { bidan, pasien, admin }
```

For P0 Supabase mode, read the role from server-controlled `app_metadata.app_role`, not editable `user_metadata`. Never place a service-role key in Flutter.

For in-memory mode, inject a demo role; default to `AppRole.bidan` so the offline demo remains immediately usable:

```dart
RawatBundaApp(
  useSupabase: false,
  demoRole: AppRole.bidan,
)
```

Route guards are not a substitute for RLS. P0 may use synthetic data and demo guards, but real data requires server-enforced policies.

### 4.2 Role-specific navigation

Use separate route trees or shells rather than conditionally hiding buttons inside the current universal shell.

| Role | Primary destinations |
|---|---|
| Bidan | Beranda, Pasien, Profil; referral and documentation are patient-context routes |
| Pasien | Beranda, Monitoring, Profil |
| Admin | Dashboard/Master Data, Profil |

Recommended route prefixes:

```text
/bidan/home
/bidan/patients
/bidan/referrals/:referralId/response
/bidan/referrals/:referralId/timeline
/bidan/documentation/:encounterId
/bidan/profile

/pasien/home
/pasien/monitoring
/pasien/profile

/admin/facilities
/admin/profile
```

Keep legacy routes as temporary redirects only. Unauthorized navigation must redirect to the current user's role home.

### 4.3 Pasien is structurally read-only

Do not merely remove edit buttons. Create a read-only repository interface that exposes only queries:

```dart
abstract interface class PatientPortalRepository {
  Future<PatientPortalSummary> getOwnSummary();
  Future<List<MonitoringScheduleItem>> getOwnSchedule();
  Future<List<ApprovedInstruction>> getOwnInstructions();
}
```

It must have no `save`, `insert`, `update`, `submit`, or `delete` method. Patient-reported complaints can still exist in the clinical record when a bidan records them; the Pasien account itself cannot write them.

### 4.4 Facility recommendation wording

The referral UI recommends the nearest **eligible and capable** facility, not merely the nearest building. P0 eligibility is at least:

- required configured capability, such as PONEK for the synthetic scenario;
- status not marked unavailable/full;
- status source/freshness displayed or clearly labeled simulated.

Distance or estimated travel time ranks facilities only after the hard capability filter.

---

## 5. Integration contracts to agree before coding

Person A and Person B should agree these contracts first. Person B may create temporary fixtures, but the final type should have one owner.

### 5.1 Confirmed encounter input

Minimum immutable data Person B needs:

```dart
class ConfirmedEncounterSummary {
  final String patientId;
  final String pregnancyEpisodeId;
  final String encounterId;
  final String displayName;
  final int? gestationalAgeWeeks;
  final int? systolic;
  final int? diastolic;
  final List<String> confirmedSymptoms;
  final String confirmedPriorityBand;
  final List<String> priorityReasons;
  final DateTime observedAt;
  final String recordedBy;
}
```

Person B consumes this type for SOAP Objective fields, clinical handoff, and referral creation. No retyping of already confirmed values.

### 5.2 Referral response

```dart
enum ReferralResponseStatus {
  contacted,
  acceptedReported,
  declinedReported,
  moreInformationRequested,
}

enum ContactChannel { phone, whatsapp, other, simulated }

class FacilityContactEvent {
  final String facilityId;
  final ReferralResponseStatus status;
  final String contactName;
  final ContactChannel channel;
  final String responseSource;
  final String? reason;
  final DateTime recordedAt;
  final String recordedBy;
  final bool isSimulated;
}
```

Decline requires a reason. Every external response requires contact/source provenance. A simulated event must remain visibly labeled simulated.

### 5.3 Documentation state

```dart
enum DocumentStatus { draft, needsReview, signed }
```

A signed document is not silently overwritten. Later changes create a new revision or amendment.

---

## 6. Phased implementation

## Phase 0 — Stabilize and agree contracts

**Goal:** Start from a recoverable baseline and avoid merge conflicts.

Tasks:

1. Confirm the existing UI redesign has its own commit.
2. Create Person B's branch from the agreed integration branch.
3. Recover/create the missing Supabase migration directory, or explicitly mark Supabase role policies deferred while using synthetic accounts.
4. Agree route names and `ConfirmedEncounterSummary` with Person A.
5. Run the current baseline:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

**Done when:** the baseline is committed, tests are green, and Person A/B own non-overlapping files.

## Phase 1 — Role model, auth resolution, and route guards

**Goal:** Every signed-in account resolves to one role and can open only its role routes.

Suggested files:

```text
lib/models/app_profile.dart
lib/repositories/profile_repository.dart
lib/state/auth_state.dart
lib/core/router/app_router.dart
lib/features/shell/bidan_shell.dart
lib/features/shell/pasien_shell.dart
lib/features/shell/admin_shell.dart
```

Tasks:

1. Add `AppRole` and `AppProfile`.
2. Extend `AppAuthState` with:
   - `isLoadingProfile`
   - `profile`
   - `role`
   - `homeLocation`
   - safe unknown/missing-role handling
3. In Supabase mode, resolve `app_metadata.app_role` after sign-in/auth refresh.
4. In in-memory mode, use the injected demo role.
5. Replace the single shell with role-specific shells.
6. Add redirects for:
   - signed out → `/login`
   - profile loading → loading screen
   - signed in on `/login` → role home
   - wrong role route → role home
   - missing/invalid role → access-configuration error, not Bidan by accident
7. Make Login navigate through `auth.homeLocation`, not hard-coded `/home`.

Tests:

- Bidan, Pasien, and Admin each land on their own home.
- Pasien cannot open a Bidan referral URL.
- Admin cannot open SOAP or patient clinical routes.
- In-memory mode defaults to Bidan and remains usable without login/network.
- Missing metadata does not grant clinical access.

**Done when:** role-aware routing works in widget tests and direct URL entry cannot cross role boundaries.

## Phase 2 — Pasien read-only and minimal Admin screens

**Goal:** Demonstrate all three roles without expanding clinical scope.

Use `lib/features/pasien_portal/`, not Person A's `lib/features/patients/`, to avoid folder and naming conflicts.

Pasien screens:

- **Beranda:** next appointment, approved reminder, approved education.
- **Monitoring:** bidan-approved monitoring schedule and previous approved summaries; no input controls.
- **Profil:** identity summary, role label, simulation notice, sign-out.

Admin screens:

- synthetic facility list;
- capability/status/freshness display;
- rule/model version display if already available;
- no clinical record or recommendation approval.

Implementation rules:

- No `TextField`, form submission, edit icon, or mutation call in Pasien screens.
- Use `PatientPortalRepository` read methods only.
- Show only synthetic/approved fields; do not reuse the full Bidan patient widget.
- Admin facility editing is out of P0 unless the core demo is already complete.

Tests:

- Pasien sees only the synthetic account's own summary.
- No data-entry control appears in Pasien routes.
- Pasien repository has no mutation API.
- Admin can see synthetic facilities but cannot reach referral/SOAP actions.

**Done when:** the three role accounts have visually distinct, permission-appropriate navigation.

## Phase 3 — Referral rework: external response recorded by Bidan

**Goal:** Remove the implied hospital login while preserving rerouting and timeline value.

Refactor targets:

```text
lib/models/referral.dart
lib/state/referral_state.dart
lib/repositories/referral_repository.dart
lib/features/receiving/receiving_facility_screen.dart
lib/features/facility_match/facility_match_screen.dart
lib/features/timeline/timeline_screen.dart
```

Prefer renaming the receiving screen to a new patient-context screen such as:

```text
lib/features/referral/record_facility_response_screen.dart
```

Tasks:

1. Remove automatic `acknowledge()` from screen rendering.
2. Replace receiving-language with `Catat Respons Faskes`.
3. Add required fields:
   - facility;
   - response status;
   - contact name;
   - contact channel;
   - response source;
   - response time;
   - decline reason when declined;
   - simulation flag for the demo tool.
4. Store each contact as a `FacilityContactEvent`/`ReferralAttempt`; do not overwrite earlier attempts.
5. On decline:
   - save the declined attempt;
   - preserve the patient/encounter/referral data;
   - return to facility matching;
   - exclude or visibly mark the previously declined facility;
   - show the next eligible alternative.
6. On externally confirmed acceptance:
   - require provenance;
   - move to the timeline;
   - label it `Diterima — dikonfirmasi dan dicatat bidan`, not app-confirmed.
7. Update timeline copy:
   - `Faskes dihubungi`
   - `Respons dicatat`
   - `Penerimaan dikonfirmasi secara eksternal`
   - `Dalam perjalanan`
   - `Tiba/serah terima`
8. Preserve in-memory and Supabase repository behavior.

Tests:

- Decline is blocked without a reason.
- Accepted/declined response is blocked without contact/source fields.
- Decline preserves the first attempt and permits second-facility selection.
- A simulated response always displays a simulation label.
- No UI claims a hospital user viewed or accepted inside RawatBunda.
- A facility lacking mandatory capability is not recommended even when closer.

**Done when:** one bidan can record Facility A declining, reroute without re-entry, record Facility B accepting externally, and complete the timeline.

## Phase 4 — Typed SOAP and document review

**Goal:** Complete documentation without depending on Gemini or audio.

Suggested files:

```text
lib/models/clinical_document.dart
lib/repositories/document_repository.dart
lib/state/documentation_state.dart
lib/features/documentation/narrative_input_screen.dart
lib/features/documentation/soap_review_screen.dart
lib/features/documentation/handoff_preview_screen.dart
lib/features/documentation/family_instruction_screen.dart
```

Deterministic P0 behavior:

- `S`: the bidan's typed patient-reported narrative, preserved verbatim.
- `O`: confirmed encounter observations imported from Person A's contract.
- `A`: blank until entered/confirmed by the bidan.
- `P`: blank until entered/confirmed by the bidan.
- Missing information stays blank or `belum disebutkan`; never infer `normal`.

Tasks:

1. Create `ClinicalDocument` with SOAP fields, source encounter, status, author, timestamps, and revision.
2. Create an in-memory `DocumentRepository` first.
3. Build typed narrative capture.
4. Generate the deterministic template draft.
5. Add explicit states:
   - `Draf`
   - `Perlu diperiksa`
   - `Disahkan`
6. Require the bidan to review/edit before signing.
7. Prevent direct editing of a signed revision; provide amendment/new revision instead.
8. Generate two separate previews:
   - clinical referral handoff from confirmed/signed data;
   - plain-language family instruction from bidan-approved plan and destination.
9. Keep the family document minimum-necessary; never expose the full SOAP note.

Tests:

- Objective values come from the confirmed encounter without retyping.
- Unsupported Assessment and Plan remain blank.
- A draft cannot be treated as signed.
- Signed content cannot be silently overwritten.
- Handoff excludes unconfirmed extracted/draft values.
- Family instruction excludes internal notes and full clinical history.

**Done when:** typed narrative → reviewable SOAP → signed document → separate handoff and family previews works completely offline.

## Phase 5 — Stretch: Gemini/STT adapter

Start only after Phases 1–4 and tests are green.

Architecture:

```text
Flutter audio/text
  → authenticated Supabase Edge Function
  → Gemini audio, or STT then Gemini
  → strict JSON response
  → server validation
  → existing SOAP review screen
```

Tasks:

1. Add an `AiDocumentationProvider` interface.
2. Keep `TemplateDocumentationProvider` as the default/fallback.
3. Add the cloud provider behind a Supabase Edge Function.
4. Store provider secrets server-side only.
5. Return transcript, SOAP candidates, missing fields, and source spans in strict JSON.
6. Validate patient/encounter binding, types, units, and allowed fields.
7. On timeout/error, preserve the typed narrative and return to template mode.
8. Use synthetic audio only in the hackathon.

**Done when:** disabling the network or AI provider does not break documentation or the demo.

---

## 7. File-collision strategy with Person A

| File/area | Owner | Rule |
|---|---|---|
| `app_router.dart`, `auth_state.dart`, shells | B | A supplies route names; A does not edit these during the sprint |
| `app.dart` provider registration | B coordinates | Make one scheduled integration edit rather than parallel edits |
| `features/patients/`, encounter, priority | A | B consumes public contracts only |
| `features/pasien_portal/`, admin | B | Do not reuse A's editable patient screens |
| referral models/state/screens | B | A supplies confirmed encounter seed data |
| documentation | B | Objective data comes from A's confirmed encounter contract |
| clinical rules | A | B must not change thresholds or reinterpret their meaning |

At the halfway checkpoint, integrate using fake/fixture `ConfirmedEncounterSummary` if Person A's screen is not ready. Replace the fixture at one explicit integration point later.

## 8. Suggested 30-hour schedule

| Time | Deliverable |
|---|---|
| Hour 0–1 | Clean baseline, contracts, route names, branch |
| Hour 1–4 | Role resolution, guards, role shells, tests |
| Hour 4–6 | Pasien read-only and minimal Admin screens |
| Hour 6–10 | Referral response model/screen and rerouting |
| Hour 10–14 | Typed SOAP, states, handoff/family previews |
| Hour 14–17 | Person A integration and test repairs |
| Hour 17–20 | Mobile-browser QA and demo rehearsal |
| Remaining time | Gemini/STT stretch, only if P0 remains green |

The exact clock can shift, but the order should not: roles → read-only surfaces → referral → typed documentation → integration → AI stretch.

## 9. Commit plan

Keep each commit independently testable:

1. `docs(person-b): add implementation plan and integration contracts`
2. `feat(auth): add app roles and demo role resolution`
3. `feat(navigation): add role-aware routes and shells`
4. `feat(pasien): add read-only patient portal`
5. `feat(admin): add synthetic facility configuration view`
6. `refactor(referral): model externally recorded facility responses`
7. `feat(referral): replace receiving view with bidan response recorder`
8. `feat(referral): preserve decline attempts and support rerouting`
9. `feat(documentation): add typed SOAP draft and review states`
10. `feat(documentation): add handoff and family instruction previews`
11. `test(person-b): cover roles referral responses and documents`
12. Stretch: `feat(ai): add protected Gemini documentation adapter`

Do not combine role routing, referral-state changes, and SOAP generation in one commit.

## 10. Verification matrix

Run after every phase:

```powershell
dart format lib test
flutter analyze
flutter test
flutter build web
```

Manual checks at approximately 390 × 844:

- Bidan can finish the complete flow.
- Pasien has no mutation control and cannot open Bidan URLs.
- Admin cannot open clinical routes.
- A closer but incapable facility is excluded.
- Facility A decline is preserved; Facility B can be selected without re-entry.
- External acceptance shows contact/source and does not imply a hospital login.
- SOAP remains a draft until bidan confirmation.
- In-memory mode works without login, Supabase, ML, Gemini, or network.

## 11. P0 definition of done

Person B's P0 is complete when:

- exactly three application roles route correctly;
- Pasien is read-only in UI, repository API, and intended RLS design;
- Admin has only the minimal synthetic configuration surface;
- the old receiving screen no longer acts like a hospital account;
- the bidan records external facility responses with provenance;
- declined attempts remain auditable and rerouting requires no patient-data re-entry;
- typed SOAP can be drafted, reviewed, signed, and reused for separate handoff/family documents;
- no AI, model, Supabase, or network dependency can block the scripted demo;
- formatting, analysis, tests, and web build pass.

Gemini/STT is not part of P0 completion.
