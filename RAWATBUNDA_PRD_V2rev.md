# RawatBunda Product Requirements Document

**Subtitle:** Bidan Workflow and Referral Coordination Copilot  
**Version:** 2.1 — patient-first workflow and three-role revision  
**Status:** Hackathon MVP specification; not approved for clinical deployment  
**Date:** 17 July 2026  
**Primary user:** Bidan providing ANC at a Puskesmas/FKTP  
**Authorized roles:** Bidan, Pasien, and Admin  
**Initial pathway:** Maternal ANC workflow, with hypertensive disorders including suspected pre-eclampsia as the first safety scenario  
**Previous specification:** `IBURUJUK_PRD.md` remains the detailed reference for the closed-loop referral subsystem

---

## 1. Executive summary

RawatBunda is an offline-tolerant workflow copilot that helps a bidan manage pregnant patients from one longitudinal record. The operational journey starts with an explicit patient selection, not an automatically generated diagnosis or risk screen. It helps the bidan:

1. Search for and select an existing patient or add a new patient.
2. Enter and verify the current encounter data.
3. Receive an explainable, non-diagnostic workflow recommendation from a hybrid rules-and-ML engine.
4. Confirm the next action and understand meaningful changes across visits.
5. Document the encounter once using structured data and an AI-assisted draft.
6. Match a referral to an appropriate facility and follow it until acceptance and handover.

RawatBunda does **not** diagnose pre-eclampsia, determine treatment, or replace the bidan's professional judgement. Safety-critical urgency is governed by transparent, versioned clinical rules and clinician input. Generative AI is limited to transcription, structured extraction, summarization, and draft documents that a bidan must review and sign.

### Product promise

> RawatBunda helps the bidan select the patient, capture the encounter once, understand the recommended priority and its reasons, document efficiently, and coordinate the right destination.

### Product category

**Bidan workflow and referral coordination copilot.**

### North-star metric

**Percentage of high-priority work items reviewed and given an appropriate next action within the locally approved target time.**

### Hackathon outcome

The MVP demonstrates one connected synthetic journey:

```text
login as bidan
  → patient directory
  → select an existing patient or add a new patient
  → current encounter data capture
  → safety floor plus ML workflow recommendation
  → bidan confirms or overrides the next action
  → four-visit trend
  → reviewed SOAP draft
  → capability-based facility match
  → bidan records externally confirmed accept/decline and reroutes if needed
  → referral timeline and handover
```

All people, facilities, capacity, documents, and measurements in the public demo are synthetic or simulated.

---

## 2. Why the pivot improves the product

The previous RawatBunda concept began after a bidan had already decided to refer. The mentor feedback extends the value earlier into the bidan's everyday workflow without turning RawatBunda into a diagnostic application.

The four ideas are not separate products. They share one verified pregnancy record:

| Mentor idea | Improved product definition | Appropriate technology |
|---|---|---|
| Prioritize patients after capture | Bidan selects a patient, enters the encounter, and receives an explainable operational recommendation; saved recommendations then form the worklist | Governed safety rules plus an ML recommendation that cannot lower the safety floor |
| Recommend a hospital | Eligibility filtering followed by transparent ranking of capable facilities | Constraint optimization, not diagnosis |
| Monitor weekly trends | Longitudinal ANC completeness and change monitoring at the clinically planned cadence | Transparent trend rules initially |
| AI documentation | Consented speech or text to structured draft SOAP, clinical handoff, and family instructions | Speech recognition plus schema-constrained generation |

### Important correction to the AI claim

A model trained to classify pre-eclampsia does not automatically become a patient-prioritization model when its output is renamed. A prioritization model needs a different target, such as clinician-adjudicated urgency, required assessment within a defined time, or a time-critical intervention.

The current pre-eclampsia dataset and model may remain an experimental research input, but they must not control the production queue, lower urgency, or support claims that RawatBunda knows which patient is safe to wait.

### Recommendation contract

For the hackathon, the ML component may demonstrate a recommendation after the bidan has entered the current data. Its contract is deliberately narrow:

- **Inputs:** confirmed patient/pregnancy context, current encounter values, relevant verified history, longitudinal features, missingness indicators, and timestamps.
- **Outputs:** a proposed operational band, the main contributing factors, missing or low-quality inputs, generation time, and model version.
- **Permitted action suggestions:** review now, review during this session, recheck an input, continue the bidan-approved monitoring plan, or open the referral workflow for bidan consideration.
- **Prohibited outputs:** diagnosis, certainty that the patient is safe, medication, dosage, treatment, discharge, or an autonomous referral decision.

The final displayed band is the maximum of the governed safety floor, the ML proposal, and any bidan-selected escalation. The bidan may accept, raise, or override the workflow recommendation with a recorded reason.

---

## 3. Background and user problem

Bidans already have the training and authority to conduct ANC, identify complications, document care, and refer within applicable protocols. The workflow problem is that information and next actions may be fragmented across a queue, paper or electronic records, informal messages, separate referral forms, telephone calls, and follow-up lists.

Indonesian research with primary-care midwives identified difficulties around referral consent, pre-referral care, transfer, hospital contact or refusal, admission, and handover.[^1] RawatBunda addresses the coordination and information burden surrounding these decisions; it does not claim the bidan lacks clinical competence.

### The operational problem

At the beginning of a clinic session, a bidan may need to answer:

- Who needs assessment first?
- Which patients are overdue or have unresolved abnormal findings?
- What changed since the previous visit?
- Which information is missing or stale?
- What did the bidan decide at the last visit?
- If referral is required, which facility has the necessary capability and has acknowledged the case?
- How can the same verified facts populate the record and referral without duplicate typing?

### Three Delays framing

RawatBunda can contribute to reducing parts of the established Three Delays:

1. **Decision delay:** clearer longitudinal evidence, explicit next actions, and family-facing explanation.
2. **Travel/referral delay:** capability-based destination options, contacts, acceptance, rerouting, and transport status.
3. **Care-entry delay:** structured pre-arrival handoff, acknowledgement, and receiving-team preparation.

RawatBunda cannot directly solve unavailable staff, beds, blood, operating rooms, ambulances, roads, or family finances. Product claims must reflect that limitation.

---

## 4. Vision, goals, and non-goals

### Vision

Give every bidan one trustworthy worklist in which each pregnant patient has a visible current state, evidence behind that state, an owner for the next action, and a closed loop when referral is required.

### Goals

- Reduce time to review patients who require immediate or same-session attention.
- Prevent abnormal findings, pending results, overdue contacts, and declined referrals from disappearing in a routine list.
- Show trends using dated, sourced observations rather than isolated values.
- Reduce duplicate entry between encounter notes, monitoring records, and referral documents.
- Improve completeness and speed of referral handoffs.
- Recommend only facilities that meet configured capability requirements.
- Preserve bidan authority, overrides, amendments, and signatures.
- Remain usable under intermittent connectivity, with honest online/offline status.
- Prepare the data model for future SATUSEHAT/FHIR interoperability.

### Non-goals

RawatBunda will not:

- Diagnose, confirm, or rule out pre-eclampsia or another condition.
- Display an unvalidated disease probability as operational urgency.
- Autonomously decide whom to treat, refer, medicate, admit, or discharge.
- Generate medication, dosage, stabilization, or delivery instructions.
- Allow AI to lower a bidan-selected urgency or a governed safety floor.
- Automatically send a referral or sign a clinical note.
- Treat missing data as normal data.
- Guarantee live capacity, acceptance, travel time, or patient outcome.
- Replace Buku KIA, the legal RME, local SOP, direct emergency communication, or clinical handover.
- Require all pregnant patients to have glucose or other tests every week. Monitoring cadence follows the approved ANC plan and individual clinical needs.[^2]
- Use real patient data, real facility capacity, or live referrals in the hackathon.
- Claim reduction in maternal mortality from an MVP or early operational pilot.

---

## 5. Product principles

1. **Bidan-led:** The bidan assesses, decides, edits, overrides, and signs.
2. **Safety floor before AI:** Deterministic, approved safety rules execute before any learned ranking.
3. **One capture, many uses:** Verified encounter data power the timeline, worklist, SOAP draft, handoff, and referral.
4. **Reasons, not mystery scores:** Users see actionable bands and evidence, not false precision.
5. **Missing is not normal:** Missing, stale, implausible, or unverified data are visible states.
6. **No-delay design:** Emergency care never waits for optional fields, AI, internet, or digital acceptance.
7. **Hard constraints before optimization:** Facility capability and clinical suitability precede distance, load balancing, or administrative convenience.
8. **Draft before record:** AI output is never final until reviewed and signed.
9. **Provenance everywhere:** Values and generated statements retain source, time, author, and verification status.
10. **Minimum necessary disclosure:** Clinical handoff, family instructions, transport view, and analytics contain different levels of detail.
11. **Honest operational state:** Saved offline is never presented as transmitted; recommended is never presented as accepted.
12. **Configurable governance:** Rules, fields, timers, documents, and capability definitions require an accountable clinical or operational owner.

---

## 6. Users, roles, and jobs to be done

RawatBunda has exactly three application roles. A hospital employee, referral coordinator, or receiving-facility user is not a fourth RawatBunda role in the MVP.

### 6.1 Bidan

**Jobs:**

- Search and select an existing patient or add a new patient before starting an encounter.
- Enter and verify current encounter data before requesting a recommendation.
- Review the recommendation, its reasons, missing inputs, model/rule version, and next-action suggestion.
- Start the day with saved patient recommendations and due tasks instead of manually reconstructing urgency.
- Open one patient record and understand the current pregnancy, recent changes, missing information, and outstanding plan.
- Record an encounter quickly using structured entry, voice, or text.
- Produce complete documentation without retyping the same facts.
- Initiate and track an appropriate referral.

**Success:** The right patient is reviewed at the right time, the next action is owned, documentation is signed, and any referral is acknowledged and closed.

### 6.2 Pasien

**Jobs:**

- View only their own bidan-approved appointment, monitoring schedule, education, and referral/family instructions.
- Receive minimum-necessary reminders without an unexplained clinical risk score.
- Submit symptoms or home measurements as `patient-reported` information for bidan verification where that workflow is enabled.
- Review consent and notification preferences.

**Limits:** Pasien cannot edit facility-measured observations, view another patient, approve an ML recommendation, sign SOAP documentation, select a facility, or change referral status.

### 6.3 Admin

**Jobs:**

- Manage account activation and assign one of the three roles.
- Maintain synthetic/configured facility capabilities, contacts, service status, and status freshness.
- Maintain approved rule, model, document-template, and notification configuration with version history.
- Review audit and de-identified operational metrics within authorized scope.

**Limits:** Admin does not make clinical decisions, approve recommendations, sign SOAP notes, or routinely browse full patient records. Break-glass or support access requires a separately governed audit process.

### 6.4 External facility interaction

The receiving facility remains an external actor or future integration, not an authenticated RawatBunda role. In the MVP, the bidan contacts the facility through the approved external channel and records the named contact, response, time, reason, and source. A synthetic response simulator may be used during the demo, but it is not a fourth user account.

### 6.5 Role-permission summary

| Capability | Bidan | Pasien | Admin |
|---|---:|---:|---:|
| Select/add patient and record encounter | Yes | No | No |
| View full assigned clinical record | Yes | Own approved summary only | No by default |
| Submit patient-reported information | Can enter/verify | Own record only | No |
| Review ML/rule recommendation | Yes | No | Configuration metadata only |
| Review and sign SOAP | Yes | No | No |
| Choose referral destination and record response | Yes | No | No |
| View family/referral instructions | Can author/approve | Own approved copy | No |
| Manage users, facilities, rules, and model versions | No | No | Yes |

---

## 7. End-to-end workflow

### 7.1 Patient directory and selection

1. Bidan opens `Pasien` and searches by the approved identifiers.
2. Bidan selects an existing patient and confirms the active pregnancy episode.
3. If no record exists, bidan selects `Tambah pasien`, enters the minimum identity and pregnancy fields, reviews any duplicate warning, and saves the new record.
4. RawatBunda does not generate a recommendation until one patient and one active encounter are confirmed.

### 7.2 Encounter data input

1. RawatBunda shows prior observations, data freshness, due tasks, and minimum information still required.
2. Bidan records current symptoms, observations, relevant history updates, and available results.
3. Plausibility, unit, timestamp, and duplicate validation run immediately.
4. Bidan corrects or verifies flagged inputs and submits the encounter for recommendation.

### 7.3 Rules-and-ML recommendation

1. Governed local safety rules establish a non-negotiable minimum urgency.
2. The ML model processes only the approved, versioned feature set and returns a proposed operational band and explanation factors.
3. RawatBunda combines the safety floor and ML proposal without allowing the ML output to lower urgency.
4. The result screen shows the recommendation, reasons, missing inputs, data time, rule/model version, and permitted next workflow actions.
5. The bidan performs the clinical assessment and accepts, raises, or overrides the recommendation with an auditable reason.
6. The confirmed state updates `Prioritas Hari Ini`, trends, and due tasks.

### 7.4 Documentation

1. Bidan starts push-to-talk, uploads a short recording, or types a narrative for the confirmed encounter.
2. A protected backend sends the audio to a configured speech-capable provider or sends an existing transcript to the configured LLM.
3. RawatBunda returns a transcript plus schema-constrained extracted fields and highlights uncertain clinical entities.
4. Proposed values are shown beside their transcript source.
5. The bidan accepts, edits, or rejects each critical extraction.
6. RawatBunda generates a draft SOAP note from confirmed facts.
7. The bidan reviews and signs; only the signed revision becomes final.

### 7.5 Plan and monitoring

The bidan records an approved next action such as routine follow-up, earlier review, measurement repeat, test, consultation, education, or referral. Every task has an owner, due time/date, status, and resolution. Patient-reported submissions remain pending until reviewed by a bidan.

### 7.6 Referral

1. The bidan decides whether to open the referral workflow and records the required capability or pathway.
2. RawatBunda removes facilities that fail mandatory constraints.
3. It presents up to three ranked candidates with explanations and status freshness.
4. The bidan selects the destination and contacts it through the approved channel.
5. The bidan records `dihubungi`, `diterima`, `ditolak`, or `perlu informasi`, including contact name, timestamp, reason, and source.
6. A decline surfaces the next eligible facility without re-entering patient information.
7. Departure, arrival, handover, and feedback are recorded in one timeline.

### 7.7 Pasien experience

The patient sees only their own bidan-approved schedule, reminders, education, and family/referral instructions. Any symptom or home-measurement submission is labeled patient-reported and cannot change clinical records or priority until a bidan reviews it.

### 7.8 Admin workflow

Admin manages user roles, facility master data, model/rule versions, and audit views. Admin cannot perform the bidan's clinical steps or mark a referral accepted on behalf of a facility.

### 7.9 Emergency bypass

- A persistent message states that emergency action and direct communication must not wait for RawatBunda.
- Required-but-missing fields are marked, but optional fields never block an emergency referral.
- Offline mode provides cached contacts and the existing emergency pathway; it does not imply a facility has received the case.

---

## 8. Module A — Prioritas Hari Ini

### 8.1 Output bands

The MVP uses three actionable priority bands rather than a 0–100 score, plus an independent data-quality state that can appear on any band:

| Band | Meaning | Default workflow |
|---|---|---|
| **Darurat — ikuti protokol sekarang** | A clinician selection or governed danger rule requires immediate action | Pin to top; show emergency bypass and direct communication |
| **Prioritas — sesi ini** | Needs earlier bidan review during the current session | Place before routine queue; show reasons |
| **Rutin/terjadwal** | No higher-priority signal based on currently verified data | Order by appointment/arrival and waiting time |
| **Data perlu diverifikasi** *(cross-cutting state)* | Critical input is missing, stale, implausible, or conflicting | Request assessment/recheck; never interpret as low risk |

`Data perlu diverifikasi` may coexist with an urgent band. Missing data must not hide known danger information.

### 8.2 Recommendation and queue sequence

The current encounter recommendation is calculated only after the bidan selects or creates a patient and submits verified input. The engine then:

1. validates the encounter and exposes missing/invalid fields;
2. applies bidan-selected urgency and governed hard safety rules;
3. requests an ML proposal from the approved model when available;
4. combines the outputs without allowing ML to lower the safety floor;
5. shows the proposed band and evidence for bidan confirmation; and
6. saves the confirmed recommendation so the patient appears in `Prioritas Hari Ini`.

The saved worklist uses safety-first ordering: confirmed emergency/safety floor, unresolved referral or overdue action, recommended operational band, and then appointment/arrival time. It never treats a hidden weighted score as proof of clinical safety.

### 8.3 Priority inputs

- Current verified observations and their freshness.
- Relevant patient-reported symptoms.
- Pregnancy episode and relevant history.
- Change from personal baseline and prior visits.
- Repeat abnormal or conflicting measurements.
- Missed or overdue planned action.
- Pending result or referral state.
- Clinician-entered urgency and override.
- Data completeness and validity.

### 8.4 Functional requirements

- **PRI-001:** Load 30 synthetic pregnancies and group them by operational band.
- **PRI-002:** Show two to four concise reasons for every non-routine item.
- **PRI-003:** Link each reason to the exact observation, timestamp, and source.
- **PRI-004:** Re-evaluate after verified new data, a correction, a task update, or referral event.
- **PRI-005:** Never allow a model to lower the governed safety floor or bidan-selected urgency.
- **PRI-006:** Allow the bidan to raise urgency immediately.
- **PRI-007:** Require user, time, and reason when lowering or dismissing a warning; preserve the original event.
- **PRI-008:** Display the active rule/model version and generation time.
- **PRI-009:** Expire priorities when the underlying information becomes stale or materially changes.
- **PRI-010:** Never state that a routine position proves a patient is clinically safe.
- **PRI-011:** Do not run the recommendation without a confirmed patient, active pregnancy episode, and encounter.
- **PRI-012:** Show model/rule version, input time, missing inputs, and two to four understandable reasons.
- **PRI-013:** Require explicit bidan confirmation or override before the recommendation becomes the current operational state.
- **PRI-014:** Record the raw ML proposal separately from the final rule-and-bidan-governed state.

### 8.5 ML readiness requirement

The hackathon may demonstrate an ML recommendation using synthetic data, but this is product-flow validation rather than clinical validation. Before real use, the model must be trained or relabeled against a locally relevant target such as expert urgency band, required response time, or time-critical intervention. It must be evaluated prospectively in silent mode before affecting a live queue. A pre-eclampsia classifier cannot be presented as a validated prioritization model merely by mapping its probability to these bands.

---

## 9. Module B — Pantau Bunda

### 9.1 Monitoring definition

RawatBunda monitors longitudinal ANC completeness and change at the clinically planned cadence. It does not prescribe identical weekly measurements for every pregnancy. WHO guidance supports repeated ANC contacts and routine monitoring such as blood pressure and weight, while glucose screening or ongoing monitoring depends on timing and clinical context.[^2]

### 9.2 Minimum longitudinal record

**Pregnancy episode:**

- Gestational-age basis, HPHT/HPL when known.
- Gravida, para, abortus.
- Relevant previous pregnancy complications.
- Relevant medical history.
- Baseline height, weight, and BMI where available.

**Encounter observations, when performed:**

- Systolic and diastolic blood pressure, including repeat-reading context.
- Weight and other locally approved ANC measurements.
- Symptoms and fetal assessment recorded by the clinician.
- Urine protein, glucose, haemoglobin, or other test results when indicated/performed.
- Plan, owner, and due date.

SATUSEHAT represents clinical measurements as timestamped `Observation` resources and supports provenance such as performer, method, device, interpretation, and reference range.[^3]

### 9.3 Trend logic for MVP

- Threshold crossing from an approved rule.
- Sustained or repeated abnormal observation.
- Meaningful change from the patient's previous verified values.
- Rate of change over a configured period.
- Conflicting or implausible entries that require recheck.
- Missed visit, overdue action, unread result, or unresolved referral.

Trend output must say **what changed and requires review**, not declare a diagnosis.

### 9.4 Functional requirements

- **MON-001:** Display at least four dated encounters in chronological order.
- **MON-002:** Preserve value, unit, observation time, entry time, source, author, and verification status.
- **MON-003:** Distinguish facility-measured, patient-reported, imported, calculated, and AI-extracted values.
- **MON-004:** Never connect or impute missing values as if they were measurements.
- **MON-005:** Show the raw observations behind each trend signal.
- **MON-006:** Convert every follow-up signal into an owned task with due date/time and status.
- **MON-007:** Deduplicate repeated alerts and record acknowledgement/resolution.
- **MON-008:** Recompute trends after an audited correction without erasing the original.
- **MON-009:** Do not use weight or glucose alone as a pre-eclampsia indicator.
- **MON-010:** Let approved local protocols configure required fields, cadence, thresholds, and expiry.

---

## 10. Module C — Rujuk Tepat

### 10.1 Product role

RawatBunda helps the bidan find the shortest path to **definitive capable care**, not merely the nearest building.

### 10.2 Hard eligibility constraints

Before ranking, a facility must satisfy all mandatory requirements configured for the referral pathway, for example:

- Appropriate maternal/newborn emergency service level.
- Required obstetric, surgical, anaesthesia, laboratory, blood, critical-care, or newborn capability.
- Operational eligibility to receive the type of referral.
- Ability to be contacted or acknowledged through the approved pathway.

Exact requirements are set by the authorized clinical/referral network; the hackathon uses clearly simulated capabilities.

### 10.3 Soft ranking factors

Only eligible facilities are ranked using:

1. Current acceptance/availability state and freshness.
2. Estimated travel time and transport feasibility.
3. Ability to respond within the configured operational target.
4. Referral-network rules and administrative compatibility.
5. Patient preference where appropriate.
6. Load balancing only after clinical capability is satisfied.

### 10.4 Recommendation output

Show up to three candidates. Each candidate displays:

- Matched mandatory capabilities.
- Missing or unknown information.
- Estimated travel time and source.
- Availability/acceptance status.
- Who last verified the status and when.
- Why it ranks above alternatives.
- Direct-contact fallback.

Example:

> Direkomendasikan karena menerima rujukan, memiliki kapabilitas A dan B, estimasi perjalanan 24 menit, dan status diperbarui 6 menit lalu.

### 10.5 Functional requirements

- **REF-001:** Exclude facilities missing a mandatory capability from the recommended set.
- **REF-002:** Never represent cached or stale capacity as live.
- **REF-003:** Distinguish `candidate`, `selected`, `contacted`, `accepted-reported`, `declined-reported`, `in transit`, and `handover complete`.
- **REF-004:** Require bidan confirmation before contact/send.
- **REF-005:** Allow the bidan to choose another eligible facility and optionally record a reason.
- **REF-006:** When a decline is recorded, require reason, timestamp, contact/channel, recording user, and response source.
- **REF-007:** Surface the next eligible option without re-entering the case.
- **REF-008:** Provide a phone/escalation fallback and prevent waiting for the app in emergencies.
- **REF-009:** Show facility-status freshness and confirmation source.
- **REF-010:** Preserve a complete referral event timeline through handover.
- **REF-011:** Do not use protected characteristics or ability to pay to reduce clinical priority.
- **REF-012:** Map the future referral request to SATUSEHAT/FHIR `ServiceRequest`, which supports subject, performer, location, reason, and supporting clinical information.[^4]
- **REF-013:** Never claim that a facility accepted unless the status source is explicitly `bidan-recorded external confirmation` or a verified integration; a demo simulator must remain labeled simulated.

---

## 11. Module D — Catat Cepat

### 11.1 Purpose

Catat Cepat reduces duplicate documentation. It converts consented push-to-talk or typed information into proposed structured fields and draft documents. It does not replace the legal author or make clinical decisions.

### 11.2 Provider architecture

The implementation is provider-agnostic behind one protected backend interface. Two supported patterns are:

1. **Fastest P0 path — direct audio understanding:** record a short audio clip, send it from Flutter to a protected backend/edge function, and let Gemini return a transcript plus schema-constrained JSON. Gemini officially supports audio transcription and structured output.[^11]
2. **More controlled path — dedicated STT then LLM:** use Google Cloud Speech-to-Text or another approved speech service for the transcript, then send the transcript to Gemini or another LLM to extract structured fields and draft SOAP. Google recommends a dedicated Speech-to-Text API for real-time transcription.[^11][^12]

Structured output guarantees conformance to the requested JSON shape, not that clinical values are semantically correct. The backend and bidan must still verify numbers, units, negation, identity, and clinical meaning.[^12]

For the hackathon, use only synthetic speech and data. Flutter calls the backend; the Gemini or other provider key is stored only in server-side secrets. Typed input and a deterministic SOAP template remain the no-network fallback.

### 11.3 Capture workflow

1. Confirm patient and active encounter.
2. Display recording state and obtain the approved notice/consent or other legally reviewed basis.
3. Capture a short push-to-talk audio clip or typed narrative.
4. Send it through the protected provider adapter and retain the transcript/source during review.
5. Return schema-constrained JSON containing transcript segments, proposed facts, SOAP candidates, missing fields, and source spans.
6. Highlight low-confidence words, negations, names, numbers, units, dates, medications, doses, and allergies.
7. Require explicit confirmation for critical extracted values.
8. Generate documents only from verified structured data and clearly attributed narrative.
9. Bidan reviews a diff, edits, and signs.

### 11.4 SOAP draft rules

SOAP is explicitly recognized in Kementerian Kesehatan's professional standard for bidan as a format for complete, accurate, concise, clear, and accountable progress notes.[^10] The exact local template and required fields nevertheless remain configurable.

- **S — Subjective:** Patient-reported complaint, symptoms, onset, relevant history, adherence, and other statements actually captured.
- **O — Objective:** Only verified observations and available results, with value, unit, time, and source.
- **A — Assessment:** Only an assessment/problem statement dictated, entered, or confirmed by the bidan. AI must not invent a diagnosis.
- **P — Plan:** Only actions, education, tests, consultation, follow-up, or referral entered or confirmed by the bidan. AI must not invent medication or treatment instructions.

When information is absent, leave it blank or mark `belum disebutkan`; never infer `normal`.

Every draft displays:

> DRAF AI — belum menjadi rekam medis sampai diperiksa dan disahkan bidan.

### 11.5 Separate generated outputs

#### A. Clinical referral/handoff

Designed for the receiving team, preferably as a concise one-page structured handoff:

- Patient identity and pregnancy context.
- Referral reason and bidan-selected urgency.
- Current observations and times.
- Relevant history, allergies, and confirmed medications.
- Available results and longitudinal change.
- Actions already performed and response, if entered.
- Requested capability.
- Sender, accepting person/facility, contact, transport, and departure information.

#### B. Patient/family instructions

Plain Bahasa Indonesia containing only approved minimum information:

- Why transfer or follow-up is recommended without an AI diagnosis.
- Destination, contact, and transport plan.
- Documents/items to bring.
- Bidan-approved instructions and when to use existing emergency channels.

The family document is not the clinical referral letter and must not expose the full record.

### 11.6 Functional requirements

- **DOC-001:** Recording cannot start without a confirmed patient and encounter.
- **DOC-002:** Provide typed/prepared transcript fallback when speech is unavailable.
- **DOC-003:** Keep the transcript visible during review.
- **DOC-004:** Highlight uncertain clinical entities and require verification of critical values.
- **DOC-005:** Never silently overwrite a manually verified observation.
- **DOC-006:** Treat dictated content as data, not as instructions to the generative model.
- **DOC-007:** Link every generated fact to a structured field or transcript segment.
- **DOC-008:** Use states `AI draft → bidan reviewed → signed/final`.
- **DOC-009:** Only the signed revision may populate the final record or sent referral.
- **DOC-010:** Preserve author, editor, signer, timestamps, and version history.
- **DOC-011:** Prefer deleting raw audio after verified transcription for the MVP; production retention requires an approved policy.
- **DOC-012:** Generate clinical handoff and family instructions as separate artifacts.
- **DOC-013:** Block unsupported diagnosis, medication, dosage, or treatment generation.
- **DOC-014:** Send third-party AI requests only through a protected backend; never embed provider secrets in Flutter.
- **DOC-015:** Isolate Gemini or any alternative behind an `AiDocumentationProvider` interface so the provider can change without rewriting the UI.
- **DOC-016:** Require a strict JSON schema and server validation; reject unknown fields and values that fail type, unit, range, or patient/encounter binding checks.
- **DOC-017:** Show a recoverable error and preserve typed/manual documentation when the speech or LLM provider is unavailable.
- **DOC-018:** Do not use submitted patient/audio data for model training unless a separate, explicit, legally approved process exists.

SATUSEHAT provides `Composition` for structured clinical documents and `DocumentReference` for governed document metadata or attachments.[^5][^6]

---

## 12. Information architecture and key screens

Navigation and permissions are role-specific. The bidan's main navigation becomes `Beranda`, `Pasien`, and `Profil`; referral is a patient-context workflow rather than a separate global role or receiving portal.

### Authentication and role routing

- After login, route the user based on exactly one role: `bidan`, `pasien`, or `admin`.
- Deny unauthorized routes in both the UI and backend/RLS; hiding a button is not authorization.
- The public demo uses synthetic accounts and prominently labels all data simulated.

### Bidan — Beranda

- `Prioritas Hari Ini` counts.
- Saved recommendation and due-task summary.
- Reason chips and next actions.
- Pending referral summary.

### Bidan — Pasien

- Search and filter the patient directory.
- Select a patient to open the current pregnancy episode.
- `Tambah pasien` action with minimum identity/pregnancy fields and duplicate warning.
- No recommendation is shown for a new patient until encounter data are submitted.

### Bidan — Patient overview

- Identity and pregnancy summary.
- Current operational band and evidence.
- Latest observations and four-visit trends.
- Symptoms, history, unresolved tasks, and recent notes.
- Actions: `Catat kunjungan`, `Buat catatan`, `Mulai rujukan`.

### Bidan — Record encounter and recommendation

- Structured measurements with visible units.
- Symptoms and free narrative.
- Data-quality validation.
- `Dapatkan rekomendasi` action after required data validation.
- Result screen with band, safety floor, ML proposal, reasons, missing inputs, version, and confirm/override actions.
- Save the bidan-confirmed state and update worklist/trends.

### Bidan — Documentation review

- Audio controls or typed transcript.
- Transcript and confidence highlights.
- Extracted structured fields.
- SOAP sections and source links.
- `Draf`, `Perlu diperiksa`, and `Disahkan` states.

### Bidan — Rujukan within a patient

Retain and extend the existing flow:

1. Case/referral review.
2. Facility matching.
3. Bidan-recorded external facility response.
4. Timeline and handover.

### Pasien

- `Beranda`: own approved next appointment, reminders, and education.
- `Monitoring`: optional symptom/home-measurement submission, visibly pending bidan verification.
- `Profil`: own identity summary, notification and consent preferences.
- No clinician queue, ML score, SOAP editor, facility administration, or other patient's data.

### Admin

- `Dashboard`: de-identified operational health and audit summary.
- `Master Data`: users/roles, facilities, capabilities, contacts, rule versions, model versions, and templates.
- `Profil`: admin identity, security, and sign-out.
- No clinical recommendation approval or SOAP signature.

### Profil shared requirements

- User identity and one assigned role.
- Connectivity and synchronization state.
- Data and AI limitations.
- Rule/model version.
- Sign-out.

---

## 13. Hackathon scope

### 13.1 P0 — must build

- Three role-gated synthetic accounts: Bidan, Pasien, and Admin; the bidan journey receives the deepest implementation.
- Synthetic patient directory with search, patient selection, and `Tambah pasien`.
- Encounter input is blocked until a patient and pregnancy episode are selected.
- Three operational bands plus the separate `Data perlu diverifikasi` state, with exact, understandable reasons.
- Deterministic safety rules; no learned model required for safety.
- A prototype ML recommendation after encounter submission, visibly labeled as synthetic/experimental and unable to lower the safety floor.
- One synthetic patient with at least four dated visits.
- BP and weight trend; optional glucose/urine protein only when marked as performed.
- Record one new encounter and update the queue immediately.
- Typed or prepared transcript fallback, with optional short-audio Gemini/STT API demonstration through a protected backend.
- Editable SOAP draft with source verification and explicit draft status.
- Referral handoff populated only from confirmed data.
- Three simulated facilities with capability, travel time, status, and freshness.
- Bidan-confirmed destination.
- Bidan-recorded external contact result with mandatory decline reason and source; optional labeled response simulator for the demo.
- Reroute without re-entry.
- Realtime or in-memory referral timeline.
- Clinical handoff and family-instruction preview.
- Minimal patient view of the approved family instruction and minimal admin view of synthetic facility configuration.
- Visible synthetic-data, decision-support, and offline/not-sent labels.

### 13.2 P1 — pilot-ready

- Real longitudinal patient and pregnancy-episode persistence.
- Role and facility-scoped authorization.
- Configurable and clinically approved priority rules.
- Durable encrypted offline store, outbox, and conflict resolution.
- Production speech recognition with typed fallback.
- Auditable document version/signature workflow.
- Facility capability and availability administration.
- Response timers, reminders, and escalation.
- Printable or PDF handoff and family instructions.
- Duplicate patient/referral detection.
- Approved messaging/notification channels.
- SATUSEHAT sandbox mapping and conformance tests.
- Co-design and usability testing with bidans and receiving staff.
- Patient-facing usability and comprehension testing.

### 13.3 P2 — validated deployment

- Prospective silent-mode evaluation of any learned prioritization signal.
- Locally validated ranking across multiple Indonesian sites.
- Live facility and transport integrations with accountable status owners.
- Regional language/accent speech evaluation.
- Additional maternal pathways, each with separate protocol governance.
- Supervisor and referral-network analytics.
- Model drift, subgroup, calibration, and safety monitoring.

### 13.4 Explicitly excluded from hackathon

- Real patients or live hospital status.
- Automatic diagnosis, treatment, referral, or signed documentation.
- An authenticated receiving-facility role or production hospital portal.
- Continuous ambient recording.
- Full RME replacement.
- Production SATUSEHAT integration.
- A claim that the existing PE model prioritizes all maternal incidents.

---

## 14. P0 acceptance criteria

### Roles and patient selection

- Login routes a synthetic user only to the Bidan, Pasien, or Admin experience assigned to that account.
- A bidan can search and select an existing synthetic patient.
- `Tambah pasien` creates a synthetic patient and active pregnancy episode after required-field and duplicate checks.
- No encounter or recommendation can be created without a selected patient and active pregnancy episode.
- Pasien can view only their own approved summary; Admin cannot sign documentation or approve clinical recommendations.

### Priority queue

- After current encounter input is submitted, the selected patient receives one primary operational band; any applicable `Data perlu diverifikasi` state is shown separately.
- The result separates governed safety floor, raw ML proposal, and final bidan-confirmed state.
- A synthetic emergency scenario always appears at the top.
- Every non-routine item shows its triggering observations and timestamps.
- New verified input re-evaluates the band without restarting the app.
- Bidan override records user, time, and reason.
- No screen calls the output a diagnosis or unvalidated disease probability.
- Saving the result updates `Prioritas Hari Ini`; patients without adequate current data remain visibly `belum dinilai`, not routine.

### Monitoring

- At least four dated encounters are shown in order.
- Values display units, dates, sources, and verification state.
- Missing data remain visibly missing.
- A trend alert links to the observations that generated it.
- A task has owner, due date/time, acknowledgement, and resolution.

### Documentation

- A transcript produces all four SOAP sections.
- Extracted numbers, units, and negations are visibly reviewable.
- Unsupported information remains blank rather than fabricated.
- Assessment remains incomplete if the bidan did not provide one.
- Note remains `Draf AI` until the bidan confirms it.
- Only confirmed data populate the referral handoff.
- Clinical handoff and family instructions are separate.
- Provider/API failure preserves the encounter and offers typed/manual SOAP completion.

### Facility matching

- A facility missing a mandatory capability is not recommended.
- Every candidate shows explanation and status timestamp.
- At least one alternative is shown.
- The bidan confirms the destination before send.
- A decline requires a reason and surfaces the next eligible candidate.

### Closed-loop referral

- The bidan can record an externally confirmed accept/decline response with contact, channel, timestamp, reason, and source.
- A synthetic automated response is visibly labeled simulated and does not imply real hospital connectivity.
- Timeline records event and elapsed time.
- A decline does not require re-entering patient or encounter data.

### Safety

- Missing optional information never blocks an emergency send.
- Offline mode never claims the referral was transmitted.
- AI cannot lower the safety tier or sign a document.
- All demo content is visibly synthetic/simulated.

---

## 15. Data model

### 15.1 Core entities

- `User` with exactly one `app_role: bidan | pasien | admin`
- `BidanProfile`, `PatientProfile`, and `AdminProfile`
- `PatientAccess` or assignment relationship
- `Organization` and `Facility`
- `FacilityCapability`
- `FacilityStatus` with source and freshness
- `Patient`
- `PregnancyEpisode`
- `Encounter`
- `Observation`
- `SymptomOrQuestionnaireResponse`
- `Task`
- `PrioritySnapshot`
- `AlertEvent`
- `Transcript`
- `DocumentDraft`
- `SignedDocument`
- `ReferralCase`
- `ReferralAttempt`
- `FacilityContactEvent` with channel, contact, response, source, and timestamp
- `TransportEvent`
- `AuditEvent`

### 15.2 Observation provenance

Every clinical value stores:

```text
patient_id
pregnancy_episode_id
encounter_id
observation_type
value
unit
observed_at
entered_at
entered_by
source_type: manual | device | patient_reported | imported | AI_extracted | derived
verification_status
method/device when available
supersedes_observation_id when corrected
```

Clinical observations are append-only. Corrections create an amendment relationship; they do not silently delete history.

### 15.3 Authorization rules

- Bidan may access only patients assigned through the approved facility/care relationship and may create/sign only under their own identity.
- Pasien may read only their own approved summary/documents and create only patient-reported submissions for their own record.
- Admin may manage accounts, facility/configuration metadata, and authorized audit/aggregate views, but has no ordinary clinical-note signing permission.
- Facility response is an event with provenance, not a fourth application user.

### 15.4 Algorithm provenance

Every priority, trend, or recommendation stores:

```text
algorithm_or_rule_id
version
intended_use
input_ids and timestamps
missing_inputs
generated_at
output_band_or_rank
explanation
reviewing_user
override and reason
software/model hash where applicable
```

---

## 16. Technical architecture

### 16.1 Hackathon architecture

Build on the existing application:

```text
Flutter UI
  → Provider state
  → repository interfaces
      → in-memory synthetic demo
      → Supabase mode for auth/realtime
```

Recommended additions:

- Role-aware router plus backend/RLS authorization for `bidan`, `pasien`, and `admin`.
- `PatientRepository`, `EncounterRepository`, `TaskRepository`, and `DocumentRepository`.
- Local deterministic rule/trend service in Dart plus an `MlRecommendationService` adapter.
- Facility eligibility and ranking service with visible factors.
- Protected backend/edge function exposing a provider-neutral `AiDocumentationProvider`.
- Template fallback when AI/network is unavailable.

```text
Flutter audio/text
  → authenticated Supabase Edge Function
      → option A: Gemini audio → transcript + structured JSON
      → option B: Speech-to-Text → transcript → Gemini/LLM structured JSON
  → server schema and clinical-field validation
  → bidan review/edit/sign
```

### 16.2 Offline truth

The following can work locally after data is available:

- Patient list and cached record.
- Encounter entry.
- Data validation.
- Deterministic priority and trend rules.
- Document templates.
- Cached facility directory and contacts.

The following require connectivity unless a future on-device implementation exists:

- Cloud speech recognition.
- Cloud LLM generation.
- Live facility status and acceptance.
- Cross-device realtime synchronization.

Required offline copy:

> Offline — data tersimpan di perangkat, tetapi rujukan belum terkirim dan status fasilitas mungkin tidak terbaru.

### 16.3 AI boundary

- Emergency rules run locally and independently of AI availability.
- A language model returns schema-constrained JSON plus generated text, not arbitrary application actions.
- Server validates schema, allowed fields, patient/encounter binding, and source references.
- Flutter never contains a service-role or AI-provider secret.
- A model output cannot directly mutate a signed record or send a referral.
- Speech/LLM providers are replaceable adapters; selecting Gemini is an implementation choice, not a product dependency.

---

## 17. Privacy, legal, and governance requirements

Before any real-patient pilot:

- Appoint a clinical safety owner, privacy/data owner, security owner, and referral-network operational owner.
- Obtain Indonesian legal/regulatory review for intended use and AI processing.
- Apply patient-assignment, own-record, and role-scoped authorization for Bidan, Pasien, and Admin; authenticated-only access is insufficient.
- Encrypt data in transit and at rest, including the local store.
- Log view, edit, generation, sign, export, send, and override events.
- Define correction, retention, deletion, lost-device, breach, and downtime procedures.
- Use minimum-necessary notifications and avoid sensitive lock-screen content.
- Separate permission for care delivery from permission to reuse data for model training.
- Never send identifiable health data to an unapproved consumer AI endpoint.
- Define voice-capture notice/consent, audio retention, third-party processing, and data residency requirements.
- Ensure generated documentation identifies the reviewing/signing practitioner and time.

Indonesia's Personal Data Protection Law treats health information as specific personal data, and Permenkes No. 24/2022 governs electronic medical records.[^7][^8] WHO health-AI guidance emphasizes human autonomy, transparency, safety, privacy, accountability, inclusiveness, and ongoing evaluation.[^9]

---

## 18. Success metrics

### 18.1 Primary workflow metrics

- Percentage of emergency/priority items reviewed within the locally approved target.
- Median time from priority-triggering event to bidan acknowledgement.
- Median time to record and sign an encounter.
- Percentage of overdue tasks resolved.
- Median referral decision-to-receiving-acknowledgement time.

### 18.2 Prioritization safety and quality

- Emergency under-triage rate; top safety guardrail.
- Recall of clinician-adjudicated urgent patients in the top queue positions.
- Pairwise agreement with independent expert priority.
- False alerts per bidan/day.
- Override rate and reasons.
- Performance by site, connectivity, language, gestational age, and relevant subgroup.

Do not use generic accuracy as the only prioritization metric.

### 18.3 Monitoring

- Missed deterioration signals.
- Alert precision and warning lead time.
- False alerts per patient-week.
- Task acknowledgement and resolution time.

### 18.4 Referral

- Recommended facilities meeting every mandatory capability; target 100% in governed tests.
- First-destination acceptance rate.
- Contact-initiated-to-response and decision-to-externally-confirmed-acceptance time.
- Decline/reroute rate and structured reasons.
- Stale-status errors and capability mismatches.
- Percentage of referrals with confirmed arrival and handover.

### 18.5 Documentation

- Documentation minutes per encounter.
- Required-field completeness after signature.
- Clinical-entity transcription error rate, especially numbers, units, negations, medications, and allergies.
- Unsupported statement/hallucination and omission rate.
- Bidan correction rate and time.
- Drafts reviewed before sending; target 100%.
- Unsigned draft count and age.

### 18.6 Claims boundary

The hackathon may claim an integrated workflow demonstration and measured task-time improvements in testing. It may not claim improved diagnosis, reduced maternal incidents, or reduced mortality without an appropriately designed prospective evaluation.

---

## 19. Risks and mitigations

| Risk | Potential harm | Required mitigation |
|---|---|---|
| PE classifier is relabelled as urgency | Unsupported queue decisions | Do not use it as P0 prioritization; define and collect a real urgency target |
| Missing measurement produces low priority | Urgent patient waits | `Data perlu diverifikasi`; hard-rule safety floor |
| User follows score blindly | Loss of professional judgement | Bands, reasons, raw evidence, override, no disease probability |
| Too many alerts | Alert fatigue | Tiering, deduplication, cooldown, volume monitoring |
| Trend connects missing values | False impression of stability | Preserve gaps; no clinical imputation |
| Facility status is stale | Misdirected referral | Timestamp, source, warning, direct confirmation |
| Closest hospital lacks capability | Delay to definitive care | Hard capability filter before travel-time ranking |
| Recommendation appears accepted | False assurance | Explicit selected/contacted/accepted-reported states plus contact, source, and timestamp |
| STT mishears a number or negation | Incorrect record or handoff | Confidence highlight, replay/source, explicit confirmation |
| LLM invents diagnosis/treatment | Clinical harm | Constrained schema, blocked fields, source linking, mandatory review |
| Unsigned draft is transmitted | Unverified information sent | State machine and send guard |
| Audio captured without proper basis | Privacy violation | Visible recording, approved notice/consent, minimal retention |
| Offline draft appears sent | Emergency coordination failure | Persistent offline/not-sent banner and server acknowledgement |
| Sync silently overwrites data | Loss of clinical truth | Append-only observations and human conflict resolution |
| Hackathon uses real data | Privacy and reputational harm | Synthetic-only fixtures, screenshots, logs, and recordings |

---

## 20. Evaluation and release gates

### Gate 0 — hackathon

- Synthetic data only.
- Complete P0 scripted flow.
- Automated tests for queue ordering, red-rule floor, facility eligibility, and document states.
- Visible limitations and fallback demo.

### Gate 1 — co-design

- Observe real workflows with bidans, coordinators, receiving staff, and patients/families.
- Map local ANC, referral, documentation, consent, and escalation procedures.
- Agree on terminology, minimum fields, capability definitions, and response ownership.

### Gate 2 — retrospective and simulation validation

- Independent clinical review of synthetic and de-identified test cases.
- Measure under-triage, false alerts, capability mismatch, transcription errors, omissions, and hallucinations.
- Test offline, no-response, decline, emergency bypass, and stale-capacity scenarios.

### Gate 3 — prospective silent mode

- RawatBunda records recommendations without changing the real queue or referral.
- Compare against existing practice and independent adjudication.
- Evaluate multiple sites and relevant subgroups.

### Gate 4 — controlled operational pilot

- Limited sites, hours, users, and pathways.
- Existing emergency and referral channels remain available.
- Real-time safety review, incident process, and predefined stop criteria.

No learned model may influence production priority before the relevant release gates and governance approval.

---

## 21. Hackathon demo script

### Setup

- A synthetic bidan account has a patient directory at a fictional Puskesmas.
- One existing patient and one `Tambah pasien` example are prepared.
- One patient has a new concerning observation and a worsening four-visit trend.
- Three synthetic hospitals have different capabilities, travel times, and status freshness.

### Demo

1. Login as Bidan and open `Pasien`.
2. Search and select the prepared patient; briefly show `Tambah pasien` and duplicate protection.
3. Add today's encounter and tap `Dapatkan rekomendasi`.
4. Show the governed safety floor, ML proposal, reasons, missing data, version, and bidan confirm/override action.
5. Save it and show the updated `Prioritas Hari Ini` plus four-visit trend.
6. Enter or dictate a short Bahasa Indonesia note through the protected AI endpoint.
7. Review highlighted numbers and negations.
8. Show the SOAP draft, leave unsupported Assessment information blank, then confirm the bidan's assessment and sign.
9. Start referral; show hard capability filtering and top-three explained candidates.
10. Record that Facility A declined through an external call, including reason and source.
11. Select Facility B without re-entry and record externally confirmed acceptance; no receiving-facility account is used.
12. Preview the patient's separate family instructions and complete the timeline.
13. Optionally switch to the Pasien account to show the approved instruction, then Admin to show synthetic facility configuration.

### Judge-facing message

> RawatBunda does not replace the bidan or diagnose pre-eclampsia. The bidan selects the patient and enters the encounter; RawatBunda then provides an explainable workflow recommendation, a visible trend, reviewed documentation, and a coordinated referral to an appropriate facility.

---

## 22. Roadmap for the current Flutter project

### Increment 1 — roles and patient foundation

- Add role routing for Bidan, Pasien, and Admin.
- Add synthetic patients, episodes, patient assignment, search/select, and `Tambah pasien`.
- Add required-field and duplicate checks.

### Increment 2 — encounter and recommendation

- Add patient overview and record-encounter screen.
- Add deterministic safety floor and ML recommendation adapter.
- Add recommendation review/confirm/override and reason chips.
- Convert Beranda into `Prioritas Hari Ini` from saved recommendations.

### Increment 3 — monitoring

- Add four-visit charts and trend/task logic.

### Increment 4 — documentation

- Add provider-neutral backend endpoint, transcript input, and extracted-field review.
- Connect short-audio Gemini or STT-plus-LLM processing using server-side secrets.
- Add template/AI SOAP draft with draft-review-sign states.
- Add clinical handoff and family-instruction previews.

### Increment 5 — referral and secondary role surfaces

- Populate the existing referral flow from the confirmed encounter.
- Add hard capability filtering, recommendation explanation, bidan-recorded external response, decline reason, and reroute.
- Add minimal Pasien approved-summary view and Admin synthetic-facility configuration view.

### Increment 6 — verification and pitch

- Run formatting, analysis, tests, and web build.
- Rehearse Supabase role accounts and in-memory fallback mode.
- Test the complete scripted flow at mobile-browser dimensions.
- Record a two-minute fallback video.

---

## 23. Open decisions

### Clinical/workflow

- Which identifiers and minimum fields are required to add a patient, and what is the duplicate-resolution process?
- Which national and local rules establish the initial safety floor?
- What are the exact operational bands and response targets?
- Which fields are required before routine prioritization, but non-blocking in an emergency?
- Who owns and versions rules, capability requirements, and document templates?
- Is SOAP the local required format, and is SBAR or another structure preferred for urgent handoff?

### Data/model

- What is the future prioritization target: expert band, response time, intervention, or another outcome?
- Who adjudicates training and evaluation labels?
- Which sites and populations are required for external validation?
- Is the existing PE model removed, shown only as experimental, or excluded from the demo entirely?

### Referral operations

- Who verifies facility capabilities and availability, and how often?
- Through which approved external channel does the bidan contact the receiving facility, and who is recorded as the respondent?
- What happens when all eligible facilities decline or do not respond?
- Which direct-call, PSC 119, or regional escalation pathways must remain visible?

### Documentation/privacy

- What notice or consent applies to recording and transcription?
- Is raw audio deleted after verification or retained under an approved policy?
- Which parts of generated documentation become the legal RME?
- What minimum information may be shared with family, transport, and receiving staff?

### Technology

- Will P0 send a short recorded clip directly to Gemini, or use Speech-to-Text followed by Gemini for easier transcript review?
- Which provider, region, retention setting, and contractual privacy terms are approved before any real patient data are processed?
- When should the project move from web-first to native Android for stronger offline and on-device speech support?

---

## 24. Final positioning

### One-line description

**RawatBunda is an offline-tolerant workflow copilot that helps bidans prioritize patients, monitor longitudinal change, create reviewed documentation, and close maternal referrals with an appropriate receiving facility.**

### What to say

> RawatBunda supports the bidan's workflow from today's queue to confirmed handover. It explains why a patient needs attention, shows what changed, reuses verified data for documentation, and helps coordinate an appropriate referral.

### What never to say

> Our AI diagnoses pre-eclampsia or knows better than the bidan who is safe to wait.

---

## References

[^1]: Rudiyanti N, Utomo B. “Challenges of health workers in primary health facilities in implementing obstetric emergency referrals to save women from death in Indonesia: A qualitative study.” *Belitung Nursing Journal*. 2024;10(6):644–653. https://pmc.ncbi.nlm.nih.gov/articles/PMC11586619/

[^2]: World Health Organization. “WHO recommendations on antenatal care for a positive pregnancy experience” and maternal intervention schedule. https://www.who.int/publications/i/item/9789241549912 and https://www.who.int/teams/maternal-newborn-child-adolescent-health-and-ageing/handbooks/programme-manager-s-handbook-mncah/recommendations-on-interventions-along-life-course/maternal

[^3]: SATUSEHAT Platform. `Observation` resource. https://satusehat.kemkes.go.id/platform/docs/id/fhir/resources/observation/

[^4]: SATUSEHAT Platform. `ServiceRequest` resource. https://satusehat.kemkes.go.id/platform/docs/id/fhir/resources/service-request/

[^5]: SATUSEHAT Platform. `Composition` resource. https://satusehat.kemkes.go.id/platform/docs/id/fhir/resources/composition/

[^6]: SATUSEHAT Platform. `DocumentReference` resource. https://satusehat.kemkes.go.id/platform/docs/id/fhir/resources/document-reference/

[^7]: Republic of Indonesia. Law No. 27/2022 on Personal Data Protection. https://peraturan.bpk.go.id/Details/229798/uu-no-27-tahun-2022

[^8]: Kementerian Kesehatan RI. Permenkes No. 24/2022 on Medical Records. https://jdih.kemkes.go.id/common/dokumen/2022permenkes024.pdf

[^9]: World Health Organization. “Ethics and governance of artificial intelligence for health” and guiding principles. https://www.who.int/publications/i/item/9789240029200 and https://www.who.int/news/item/28-06-2021-who-issues-first-global-report-on-artificial-intelligence-ai-in-health-and-six-guiding-principles-for-its-design-and-use

[^10]: Kementerian Kesehatan RI. *Standar Profesi Bidan*; documentation is described as complete, accurate, concise, clear, accountable, and written as SOAP progress notes. https://repositori-ditjen-nakes.kemkes.go.id/294/2/Buku%20digital%20Standar%20Profesi%20Bidan.pdf

[^11]: Google AI for Developers. “Audio understanding — Gemini API”; Gemini supports audio analysis/transcription and structured transcription output, while the documentation directs real-time transcription use cases to a dedicated Speech-to-Text API. https://ai.google.dev/gemini-api/docs/audio

[^12]: Google AI for Developers and Google Cloud. “Structured outputs — Gemini API” and “Transcribe audio from streaming input — Cloud Speech-to-Text.” Structured output guarantees schema-conforming syntax but still requires semantic/application validation. https://ai.google.dev/gemini-api/docs/structured-output and https://docs.cloud.google.com/speech-to-text/docs/streaming-recognize
