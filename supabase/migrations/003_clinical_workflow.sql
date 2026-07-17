-- RawatBunda integrated STT -> bidan review -> ML -> operational priority.
-- Apply after 002_ml_backend.sql. Migration 002 is intentionally immutable.

alter table public.patients
  add column if not exists age_years integer
    check (age_years is null or age_years between 12 and 60);

alter table public.pregnancy_episodes
  add column if not exists gravida integer not null default 1
    check (gravida between 0 and 15),
  add column if not exists para integer not null default 0
    check (para between 0 and 15),
  add column if not exists abortus integer not null default 0
    check (abortus between 0 and 15),
  add column if not exists history jsonb not null default '[]'::jsonb
    check (jsonb_typeof(history) = 'array');

create table if not exists public.stt_drafts (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  pregnancy_episode_id uuid not null
    references public.pregnancy_episodes(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending_review'
    check (status in ('pending_review', 'confirmed', 'rejected')),
  transcript text not null,
  soap_note jsonb not null default '{}'::jsonb
    check (jsonb_typeof(soap_note) = 'object'),
  extracted_model_input jsonb not null default '{}'::jsonb
    check (jsonb_typeof(extracted_model_input) = 'object'),
  extracted_clinical_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(extracted_clinical_context) = 'object'),
  extraction_warnings jsonb not null default '[]'::jsonb
    check (jsonb_typeof(extraction_warnings) = 'array'),
  audio_metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(audio_metadata) = 'object'),
  confirmed_encounter_id uuid references public.encounters(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    status = 'pending_review' or
    (reviewed_by is not null and reviewed_at is not null)
  ),
  check (
    status <> 'confirmed' or confirmed_encounter_id is not null
  )
);

create index if not exists stt_drafts_patient_created_idx
  on public.stt_drafts (patient_id, created_at desc);

create table if not exists public.encounter_clinical_details (
  encounter_id uuid primary key references public.encounters(id) on delete restrict,
  stt_draft_id uuid references public.stt_drafts(id) on delete set null,
  weight_kg double precision check (weight_kg is null or weight_kg > 0),
  height_cm double precision check (height_cm is null or height_cm > 0),
  severe_headache boolean not null default false,
  visual_disturbance boolean not null default false,
  urine_protein text not null default 'not_tested'
    check (urine_protein in ('not_tested', 'negative', 'trace', 'positive')),
  notes text not null default '',
  soap_note jsonb not null default '{}'::jsonb
    check (jsonb_typeof(soap_note) = 'object'),
  confirmed_by uuid not null references auth.users(id) on delete restrict,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.stt_drafts enable row level security;
alter table public.encounter_clinical_details enable row level security;

drop policy if exists stt_drafts_assigned_bidan_select on public.stt_drafts;
create policy stt_drafts_assigned_bidan_select
  on public.stt_drafts for select to authenticated
  using (
    exists (
      select 1 from public.patient_access access
      where access.patient_id = stt_drafts.patient_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

drop policy if exists encounter_details_assigned_bidan_select
  on public.encounter_clinical_details;
create policy encounter_details_assigned_bidan_select
  on public.encounter_clinical_details for select to authenticated
  using (
    exists (
      select 1
      from public.encounters encounter
      join public.patient_access access
        on access.patient_id = encounter.patient_id
      where encounter.id = encounter_clinical_details.encounter_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

grant select on public.stt_drafts, public.encounter_clinical_details
  to authenticated;

-- Backend-only access check performed before paid/external STT processing.
create or replace function public.assert_bidan_patient_access(
  p_patient_id uuid,
  p_pregnancy_episode_id uuid,
  p_actor_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.pregnancy_episodes episode
    where episode.id = p_pregnancy_episode_id
      and episode.patient_id = p_patient_id
  ) then
    raise exception 'pregnancy_episode_correlation_mismatch';
  end if;

  if not exists (
    select 1 from public.patient_access access
    where access.patient_id = p_patient_id
      and access.user_id = p_actor_id
      and access.relationship = 'assigned_bidan'
  ) then
    raise exception 'patient_access_denied';
  end if;

  return jsonb_build_object('allowed', true);
end;
$$;

-- Patient creation remains a backend write. It also creates the active
-- pregnancy episode and grants the creating bidan access atomically.
create or replace function public.create_patient_with_episode(
  p_created_by uuid,
  p_display_name text,
  p_age_years integer,
  p_gestational_age_weeks integer,
  p_gravida integer,
  p_para integer,
  p_abortus integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  patient public.patients%rowtype;
  episode public.pregnancy_episodes%rowtype;
  actor_role text;
begin
  select raw_app_meta_data ->> 'app_role' into actor_role
  from auth.users where id = p_created_by;
  if coalesce(actor_role, '') <> 'bidan' then
    raise exception 'bidan_role_required';
  end if;
  if length(trim(coalesce(p_display_name, ''))) = 0 then
    raise exception 'patient_name_required';
  end if;

  insert into public.patients (display_name, age_years)
  values (trim(p_display_name), p_age_years)
  returning * into patient;

  insert into public.pregnancy_episodes (
    patient_id, gestational_age_weeks, gravida, para, abortus
  ) values (
    patient.id, p_gestational_age_weeks, p_gravida, p_para, p_abortus
  ) returning * into episode;

  insert into public.patient_access (patient_id, user_id, relationship)
  values (patient.id, p_created_by, 'assigned_bidan');

  return jsonb_build_object(
    'patient_id', patient.id,
    'pregnancy_episode_id', episode.id
  );
end;
$$;

create or replace function public.create_stt_draft(
  p_patient_id uuid,
  p_pregnancy_episode_id uuid,
  p_created_by uuid,
  p_transcript text,
  p_soap_note jsonb,
  p_extracted_model_input jsonb,
  p_extracted_clinical_context jsonb,
  p_extraction_warnings jsonb,
  p_audio_metadata jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  draft public.stt_drafts%rowtype;
begin
  perform public.assert_bidan_patient_access(
    p_patient_id, p_pregnancy_episode_id, p_created_by
  );
  if length(trim(coalesce(p_transcript, ''))) = 0 then
    raise exception 'empty_transcript';
  end if;

  insert into public.stt_drafts (
    patient_id,
    pregnancy_episode_id,
    created_by,
    transcript,
    soap_note,
    extracted_model_input,
    extracted_clinical_context,
    extraction_warnings,
    audio_metadata
  ) values (
    p_patient_id,
    p_pregnancy_episode_id,
    p_created_by,
    p_transcript,
    coalesce(p_soap_note, '{}'::jsonb),
    coalesce(p_extracted_model_input, '{}'::jsonb),
    coalesce(p_extracted_clinical_context, '{}'::jsonb),
    coalesce(p_extraction_warnings, '[]'::jsonb),
    coalesce(p_audio_metadata, '{}'::jsonb)
  ) returning * into draft;

  return jsonb_build_object('draft_id', draft.id, 'created_at', draft.created_at);
end;
$$;

-- Finalize the bidan-confirmed encounter and calculate the operational queue
-- from deterministic safety rules. The experimental ML score is linked for
-- audit/display but never lowers or directly chooses the final band.
create or replace function public.confirm_assessment_workflow(
  p_encounter_id uuid,
  p_confirmed_by uuid,
  p_prediction_id uuid,
  p_stt_draft_id uuid,
  p_clinical_context jsonb,
  p_soap_note jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  encounter public.encounters%rowtype;
  draft public.stt_drafts%rowtype;
  prediction public.ml_predictions%rowtype;
  existing_snapshot public.priority_snapshots%rowtype;
  snapshot public.priority_snapshots%rowtype;
  sys double precision;
  dia double precision;
  previous_sys double precision;
  previous_dia double precision;
  danger boolean;
  urine text;
  band text := 'rutin';
  needs_review boolean := false;
  reasons jsonb := '[]'::jsonb;
  missing jsonb := '[]'::jsonb;
  field_name text;
begin
  select * into encounter
  from public.encounters where id = p_encounter_id for update;
  if not found then
    raise exception 'encounter_not_found';
  end if;

  perform public.assert_bidan_patient_access(
    encounter.patient_id, encounter.pregnancy_episode_id, p_confirmed_by
  );

  select * into existing_snapshot
  from public.priority_snapshots
  where encounter_id = p_encounter_id and state = 'confirmed'
  order by confirmed_at desc limit 1;
  if found then
    return jsonb_build_object(
      'priority_snapshot_id', existing_snapshot.id,
      'final_band', existing_snapshot.final_band,
      'needs_verification', existing_snapshot.needs_verification,
      'reasons', existing_snapshot.reasons,
      'missing_inputs', existing_snapshot.missing_inputs,
      'generated_at', existing_snapshot.generated_at,
      'idempotent_replay', true
    );
  end if;

  if p_prediction_id is not null then
    select * into prediction
    from public.ml_predictions where id = p_prediction_id;
    if not found or prediction.encounter_id <> encounter.id then
      raise exception 'prediction_encounter_mismatch';
    end if;
  end if;

  if p_stt_draft_id is not null then
    select * into draft from public.stt_drafts
    where id = p_stt_draft_id for update;
    if not found
       or draft.patient_id <> encounter.patient_id
       or draft.pregnancy_episode_id <> encounter.pregnancy_episode_id then
      raise exception 'stt_draft_correlation_mismatch';
    end if;
    if draft.status = 'rejected'
       or (draft.status = 'confirmed'
           and draft.confirmed_encounter_id <> encounter.id) then
      raise exception 'stt_draft_already_consumed';
    end if;
  end if;

  update public.encounters
  set verification_status = 'verified',
      source_type = case when p_stt_draft_id is null then 'manual'
                         else 'AI_extracted' end,
      observed_at = coalesce(
        observed_at,
        nullif(encounter.input_snapshot ->> 'measured_at', '')::timestamptz,
        now()
      )
  where id = encounter.id;

  insert into public.encounter_clinical_details (
    encounter_id,
    stt_draft_id,
    weight_kg,
    height_cm,
    severe_headache,
    visual_disturbance,
    urine_protein,
    notes,
    soap_note,
    confirmed_by
  ) values (
    encounter.id,
    p_stt_draft_id,
    nullif(p_clinical_context ->> 'weight_kg', '')::double precision,
    nullif(p_clinical_context ->> 'height_cm', '')::double precision,
    coalesce((p_clinical_context ->> 'severe_headache')::boolean, false),
    coalesce((p_clinical_context ->> 'visual_disturbance')::boolean, false),
    coalesce(nullif(p_clinical_context ->> 'urine_protein', ''), 'not_tested'),
    coalesce(p_clinical_context ->> 'notes', ''),
    coalesce(p_soap_note, '{}'::jsonb),
    p_confirmed_by
  ) on conflict (encounter_id) do nothing;

  if p_stt_draft_id is not null then
    update public.stt_drafts
    set status = 'confirmed',
        confirmed_encounter_id = encounter.id,
        reviewed_by = p_confirmed_by,
        reviewed_at = now()
    where id = p_stt_draft_id;
  end if;

  foreach field_name in array array[
    'measured_at', 'age_years', 'systolic_bp_mmhg', 'diastolic_bp_mmhg',
    'blood_sugar', 'body_temperature', 'bmi_kg_m2',
    'previous_complications', 'preexisting_diabetes',
    'gestational_diabetes', 'mental_health_indicator', 'heart_rate_bpm'
  ] loop
    if not (encounter.input_snapshot ? field_name)
       or encounter.input_snapshot -> field_name = 'null'::jsonb then
      missing := missing || jsonb_build_array(field_name);
    end if;
  end loop;
  needs_review := jsonb_array_length(missing) > 0;

  sys := nullif(encounter.input_snapshot ->> 'systolic_bp_mmhg', '')::double precision;
  dia := nullif(encounter.input_snapshot ->> 'diastolic_bp_mmhg', '')::double precision;
  danger := coalesce((p_clinical_context ->> 'severe_headache')::boolean, false)
    or coalesce((p_clinical_context ->> 'visual_disturbance')::boolean, false);
  urine := coalesce(nullif(p_clinical_context ->> 'urine_protein', ''), 'not_tested');

  if sys is null or dia is null then
    needs_review := true;
    reasons := reasons || jsonb_build_array(
      'Tekanan darah belum lengkap - perlu diverifikasi'
    );
  end if;

  if (coalesce(sys, 0) >= 160 or coalesce(dia, 0) >= 110) and danger then
    band := 'darurat';
    reasons := reasons || jsonb_build_array(
      'Tekanan darah pada ambang berat disertai gejala bahaya'
    );
  elsif coalesce(sys, 0) >= 160 or coalesce(dia, 0) >= 110 then
    band := 'prioritas';
    reasons := reasons || jsonb_build_array(
      'Tekanan darah pada ambang berat - ulangi pengukuran sesi ini'
    );
  elsif danger then
    band := 'prioritas';
    reasons := reasons || jsonb_build_array(
      'Gejala bahaya dilaporkan - periksa pada sesi ini'
    );
  elsif coalesce(sys, 0) >= 140 or coalesce(dia, 0) >= 90 then
    band := 'prioritas';
    reasons := reasons || jsonb_build_array(
      'Tekanan darah meningkat - tinjau lebih awal'
    );
  end if;

  if urine = 'positive' and band <> 'darurat' then
    band := 'prioritas';
    reasons := reasons || jsonb_build_array(
      'Protein urin positif pada kunjungan terakhir'
    );
  end if;

  select
    nullif(previous.input_snapshot ->> 'systolic_bp_mmhg', '')::double precision,
    nullif(previous.input_snapshot ->> 'diastolic_bp_mmhg', '')::double precision
  into previous_sys, previous_dia
  from public.encounters previous
  where previous.patient_id = encounter.patient_id
    and previous.id <> encounter.id
    and previous.verification_status in ('verified', 'amended')
    and previous.input_snapshot ? 'systolic_bp_mmhg'
    and previous.input_snapshot ? 'diastolic_bp_mmhg'
  order by previous.observed_at desc nulls last, previous.created_at desc
  limit 1;

  if band <> 'darurat' and (
    (sys is not null and previous_sys is not null and sys - previous_sys >= 15)
    or (dia is not null and previous_dia is not null and dia - previous_dia >= 10)
  ) then
    band := 'prioritas';
    reasons := reasons || jsonb_build_array(
      'Tekanan darah meningkat bermakna dibanding kunjungan sebelumnya'
    );
  end if;

  insert into public.priority_snapshots (
    patient_id,
    pregnancy_episode_id,
    encounter_id,
    ml_prediction_id,
    state,
    safety_floor_band,
    raw_ml_proposed_band,
    final_band,
    needs_verification,
    reasons,
    missing_inputs,
    rule_id,
    rule_version,
    model_version,
    confirmed_by,
    confirmed_at
  ) values (
    encounter.patient_id,
    encounter.pregnancy_episode_id,
    encounter.id,
    p_prediction_id,
    'confirmed',
    band,
    null,
    band,
    needs_review,
    (
      select coalesce(jsonb_agg(value), '[]'::jsonb)
      from (select value from jsonb_array_elements(reasons) limit 4) limited
    ),
    missing,
    'maternal-worklist-safety-floor',
    'demo-v1',
    case when p_prediction_id is null then null else prediction.model_version end,
    p_confirmed_by,
    now()
  ) returning * into snapshot;

  return jsonb_build_object(
    'priority_snapshot_id', snapshot.id,
    'final_band', snapshot.final_band,
    'needs_verification', snapshot.needs_verification,
    'reasons', snapshot.reasons,
    'missing_inputs', snapshot.missing_inputs,
    'generated_at', snapshot.generated_at,
    'idempotent_replay', false
  );
end;
$$;

revoke all on function public.assert_bidan_patient_access(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.create_patient_with_episode(
  uuid, text, integer, integer, integer, integer, integer
) from public, anon, authenticated;
revoke all on function public.create_stt_draft(
  uuid, uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated;
revoke all on function public.confirm_assessment_workflow(
  uuid, uuid, uuid, uuid, jsonb, jsonb
) from public, anon, authenticated;

grant execute on function public.assert_bidan_patient_access(uuid, uuid, uuid)
  to service_role;
grant execute on function public.create_patient_with_episode(
  uuid, text, integer, integer, integer, integer, integer
) to service_role;
grant execute on function public.create_stt_draft(
  uuid, uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, jsonb
) to service_role;
grant execute on function public.confirm_assessment_workflow(
  uuid, uuid, uuid, uuid, jsonb, jsonb
) to service_role;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'patients', 'pregnancy_episodes', 'encounters',
    'encounter_clinical_details', 'stt_drafts'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', table_name
      );
    end if;
  end loop;
end
$$;

comment on table public.stt_drafts is
  'Unconfirmed AI transcript, SOAP, and extracted fields. Never clinical truth.';
comment on table public.encounter_clinical_details is
  'Bidan-confirmed non-model clinical context and SOAP linked to an encounter.';
