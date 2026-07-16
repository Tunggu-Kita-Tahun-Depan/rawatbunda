# RawatBunda UI/UX Implementation Plan

## Outcome

Turn the existing four-screen referral click-through into a coherent mobile
browser experience inspired by the supplied blue, white, and lime health UI.
The redesign must preserve RawatBunda's operational purpose, safety wording,
Supabase/in-memory repositories, and two-device realtime demo.

## Information architecture

The app has three primary destinations:

1. **Beranda** — entry point, current-referral summary, and demo role shortcuts.
2. **Rujukan** — one guided four-step workflow:
   Input Data Ibu → Pilih Fasilitas → Faskes Penerima → Linimasa.
3. **Profil** — read-only demo identity, connection mode, limitations, and logout.

The future operations dashboard remains separate and is not presented as a
finished hackathon feature.

## Phase 1 — Shared foundation

Status: implemented.

- Replace the cyan seed theme with explicit RawatBunda tokens.
- Apply a soft periwinkle canvas, blue primary surfaces, white rounded cards,
  dark high-contrast text, and lime selection accents.
- Reserve red for clinical danger, failures, rejection, and logout.
- Add reusable simulation badge, page header, referral progress header, status
  pill, metric tile, and information notice.
- Constrain the web interface to a mobile-first 480 px content width.

## Phase 2 — Navigation, Home, and Profile

Status: implemented.

- Use three bottom destinations instead of treating each workflow step as an
  independent app section.
- Start signed-in and in-memory sessions on Beranda.
- Show only the current referral on Home because the repository does not expose
  history or aggregate statistics.
- Provide explicit Bidan and Faskes shortcuts for the scripted two-device demo.
- Keep Profile read-only until roles, facility membership, and profile metadata
  exist in the backend.

## Phase 3 — Referral workflow redesign

Status: implemented.

- **Input:** grouped cards, prominent blood-pressure fields, symptom chips,
  urgency selection, transparent safety trigger, and full-width action.
- **Facility match:** compact case summary, capability/status pills, clear
  selected and unavailable states, and no invented ETA or capacity.
- **Receiving facility:** incoming-referral hero, essential metrics, danger
  symptoms, explicit accept/reject actions, and unchanged realtime behavior.
- **Timeline:** blue elapsed-time hero, vertical status timeline, destination
  card, and overflow-safe scrolling.

## Phase 4 — Verification

Status: automated verification and 390 × 844 visual QA completed on
17 July 2026. Two-device Supabase rehearsal and 200% zoom checks remain manual.

1. ✅ Run `dart format lib test`.
2. ✅ Run `flutter analyze`.
3. ✅ Run `flutter test`.
4. ✅ Run `flutter build web` in configured and in-memory modes.
5. ✅ Inspect login, Home, Intake, facility matching, receiving empty state,
   and Profile at 390 × 844.
6. Test at 200% browser zoom.
7. Test Supabase mode with separate bidan and receiving-facility accounts.
8. Record the complete referral path and verify no screen implies diagnosis,
   real capacity, or real patient data.

## Acceptance criteria

- Beranda is the first authenticated screen.
- Beranda, Rujukan, and Profil are reachable from every primary screen.
- Switching tabs preserves a partially completed intake form.
- Every referral screen communicates its current step without allowing steps to
  be mistaken for unrelated app sections.
- A severe BP plus danger symptom still displays the exact demo-rule trigger.
- All facility and patient information remains visibly simulated.
- Home shows no fabricated history, response statistics, or bed availability.
- Profile shows no invented authorization role or facility assignment.
- The four-screen demo works in both in-memory and Supabase modes.
- Analyze, widget tests, and the web build complete successfully.

## After the hackathon

- Add role and facility metadata backed by authorization policies.
- Add structured decline reasons and second-facility rerouting.
- Add durable offline queueing and conflict handling.
- Add referral history and operational counts only after repository support.
- Validate accessibility and workflow wording with bidan and receiving staff.
