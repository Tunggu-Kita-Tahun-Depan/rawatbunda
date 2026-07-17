-- RawatBunda ML backend persistence.
-- Apply after 001_init.sql. All authenticated clients are read-only for ML
-- tables; service-role-only RPCs own job and prediction writes.

create extension if not exists pgcrypto;

create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  display_name text not null,
  is_synthetic boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pregnancy_episodes (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'closed')),
  gestational_age_weeks integer
    check (gestational_age_weeks is null or gestational_age_weeks between 1 and 43),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists public.patient_access (
  patient_id uuid not null references public.patients(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  relationship text not null default 'assigned_bidan'
    check (relationship in ('assigned_bidan', 'patient_self')),
  created_at timestamptz not null default now(),
  primary key (patient_id, user_id, relationship)
);

create table if not exists public.encounters (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  pregnancy_episode_id uuid not null
    references public.pregnancy_episodes(id) on delete restrict,
  observed_at timestamptz,
  entered_at timestamptz not null default now(),
  entered_by uuid not null references auth.users(id) on delete restrict,
  source_type text not null default 'manual'
    check (source_type in (
      'manual', 'device', 'patient_reported', 'imported', 'AI_extracted', 'derived'
    )),
  verification_status text not null default 'verified'
    check (verification_status in ('pending', 'verified', 'rejected', 'amended')),
  input_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(input_snapshot) = 'object'),
  input_hash text,
  created_at timestamptz not null default now(),
  check (input_hash is null or input_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists encounters_patient_observed_idx
  on public.encounters (patient_id, observed_at desc);

create table if not exists public.ml_inference_jobs (
  id uuid primary key default gen_random_uuid(),
  request_id text not null unique
    check (request_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  patient_id uuid not null references public.patients(id) on delete restrict,
  pregnancy_episode_id uuid not null
    references public.pregnancy_episodes(id) on delete restrict,
  encounter_id uuid not null references public.encounters(id) on delete restrict,
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  model_version text not null,
  schema_version text not null default '1.0',
  request_payload jsonb not null check (jsonb_typeof(request_payload) = 'object'),
  requested_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'running'
    check (status in ('queued', 'running', 'completed', 'failed')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  error_code text,
  error_message text,
  model_response jsonb,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz
);

create index if not exists ml_jobs_encounter_idx
  on public.ml_inference_jobs (encounter_id, created_at desc);

create table if not exists public.ml_predictions (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null unique
    references public.ml_inference_jobs(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  pregnancy_episode_id uuid not null
    references public.pregnancy_episodes(id) on delete restrict,
  encounter_id uuid not null references public.encounters(id) on delete restrict,
  request_id text not null,
  record_id text not null,
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  prediction_status text not null
    check (prediction_status in ('ok', 'invalid_input', 'out_of_distribution')),
  model_score double precision check (
    model_score is null or model_score between 0.0 and 1.0
  ),
  risk_signal boolean,
  risk_band text check (
    risk_band is null or risk_band in (
      'high-label-pattern-detected',
      'high-label-pattern-not-detected'
    )
  ),
  ranking_eligible boolean not null default false
    check (ranking_eligible = false),
  score_comparable_within_artifact boolean not null,
  ranking_blockers jsonb not null check (
    jsonb_typeof(ranking_blockers) = 'array' and
    jsonb_array_length(ranking_blockers) > 0
  ),
  measurement_timestamp timestamptz,
  errors jsonb not null default '[]'::jsonb
    check (jsonb_typeof(errors) = 'array'),
  warnings jsonb not null default '[]'::jsonb
    check (jsonb_typeof(warnings) = 'array'),
  model_version text not null,
  artifact_sha256 text not null check (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm text not null,
  operating_threshold double precision not null check (
    operating_threshold between 0.0 and 1.0
  ),
  score_definition text not null,
  ranking_policy text not null,
  generated_at timestamptz not null,
  validated_at timestamptz not null default now(),
  raw_response jsonb not null check (jsonb_typeof(raw_response) = 'object'),
  clinical_review_still_required boolean not null check (
    clinical_review_still_required = true
  ),
  cannot_rule_out_maternal_risk boolean not null check (
    cannot_rule_out_maternal_risk = true
  ),
  may_not_downgrade_clinician_urgency boolean not null check (
    may_not_downgrade_clinician_urgency = true
  ),
  may_not_suppress_referral boolean not null check (
    may_not_suppress_referral = true
  ),
  created_at timestamptz not null default now(),
  check (
    (
      prediction_status = 'ok' and
      model_score is not null and
      risk_signal is not null and
      risk_band is not null and
      score_comparable_within_artifact = true and
      jsonb_array_length(errors) = 0
    ) or (
      prediction_status in ('invalid_input', 'out_of_distribution') and
      model_score is null and
      risk_signal is null and
      risk_band is null and
      score_comparable_within_artifact = false and
      jsonb_array_length(errors) > 0
    )
  )
);

create index if not exists ml_predictions_encounter_idx
  on public.ml_predictions (encounter_id, created_at desc);
create index if not exists ml_predictions_patient_idx
  on public.ml_predictions (patient_id, created_at desc);

create table if not exists public.priority_snapshots (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  pregnancy_episode_id uuid not null
    references public.pregnancy_episodes(id) on delete restrict,
  encounter_id uuid not null references public.encounters(id) on delete restrict,
  ml_prediction_id uuid references public.ml_predictions(id) on delete set null,
  state text not null default 'pending_bidan_confirmation'
    check (state in ('pending_bidan_confirmation', 'confirmed', 'expired')),
  safety_floor_band text not null
    check (safety_floor_band in ('darurat', 'prioritas', 'rutin')),
  raw_ml_proposed_band text
    check (raw_ml_proposed_band is null or raw_ml_proposed_band in (
      'darurat', 'prioritas', 'rutin'
    )),
  final_band text
    check (final_band is null or final_band in ('darurat', 'prioritas', 'rutin')),
  needs_verification boolean not null default false,
  reasons jsonb not null default '[]'::jsonb
    check (jsonb_typeof(reasons) = 'array'),
  missing_inputs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(missing_inputs) = 'array'),
  rule_id text not null,
  rule_version text not null,
  model_version text,
  generated_at timestamptz not null default now(),
  expires_at timestamptz,
  confirmed_by uuid references auth.users(id) on delete restrict,
  confirmed_at timestamptz,
  override_applied boolean not null default false,
  override_reason text,
  created_at timestamptz not null default now(),
  check (
    state <> 'confirmed' or
    (final_band is not null and confirmed_by is not null and confirmed_at is not null)
  ),
  check (
    override_applied = false or
    (override_reason is not null and length(trim(override_reason)) > 0)
  )
);

create index if not exists priority_snapshots_patient_idx
  on public.priority_snapshots (patient_id, created_at desc);

alter table public.patients enable row level security;
alter table public.pregnancy_episodes enable row level security;
alter table public.patient_access enable row level security;
alter table public.encounters enable row level security;
alter table public.ml_inference_jobs enable row level security;
alter table public.ml_predictions enable row level security;
alter table public.priority_snapshots enable row level security;

drop policy if exists patients_assigned_bidan_select on public.patients;
create policy patients_assigned_bidan_select
  on public.patients for select to authenticated
  using (
    auth_user_id = auth.uid() or exists (
      select 1 from public.patient_access access
      where access.patient_id = patients.id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

drop policy if exists patient_access_own_select on public.patient_access;
create policy patient_access_own_select
  on public.patient_access for select to authenticated
  using (user_id = auth.uid());

drop policy if exists pregnancy_assigned_bidan_select on public.pregnancy_episodes;
create policy pregnancy_assigned_bidan_select
  on public.pregnancy_episodes for select to authenticated
  using (
    exists (
      select 1 from public.patient_access access
      where access.patient_id = pregnancy_episodes.patient_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

drop policy if exists encounters_assigned_bidan_select on public.encounters;
create policy encounters_assigned_bidan_select
  on public.encounters for select to authenticated
  using (
    exists (
      select 1 from public.patient_access access
      where access.patient_id = encounters.patient_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

drop policy if exists ml_jobs_assigned_bidan_select on public.ml_inference_jobs;
create policy ml_jobs_assigned_bidan_select
  on public.ml_inference_jobs for select to authenticated
  using (
    exists (
      select 1 from public.patient_access access
      where access.patient_id = ml_inference_jobs.patient_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

drop policy if exists ml_predictions_assigned_bidan_select on public.ml_predictions;
create policy ml_predictions_assigned_bidan_select
  on public.ml_predictions for select to authenticated
  using (
    exists (
      select 1 from public.patient_access access
      where access.patient_id = ml_predictions.patient_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

drop policy if exists priority_assigned_bidan_select on public.priority_snapshots;
create policy priority_assigned_bidan_select
  on public.priority_snapshots for select to authenticated
  using (
    exists (
      select 1 from public.patient_access access
      where access.patient_id = priority_snapshots.patient_id
        and access.user_id = auth.uid()
        and access.relationship = 'assigned_bidan'
    )
  );

-- Frontend-ready read models. Security invoker keeps base-table RLS active.
create or replace view public.latest_ml_predictions
with (security_invoker = true)
as
select distinct on (encounter_id)
  id,
  patient_id,
  pregnancy_episode_id,
  encounter_id,
  prediction_status,
  model_score,
  risk_signal,
  risk_band,
  model_version,
  generated_at,
  created_at
from public.ml_predictions
order by encounter_id, created_at desc;

create or replace view public.current_priority_snapshots
with (security_invoker = true)
as
select distinct on (patient_id)
  id,
  patient_id,
  pregnancy_episode_id,
  encounter_id,
  ml_prediction_id,
  safety_floor_band,
  raw_ml_proposed_band,
  final_band,
  needs_verification,
  reasons,
  missing_inputs,
  rule_id,
  rule_version,
  model_version,
  generated_at,
  expires_at,
  confirmed_at
from public.priority_snapshots
where state = 'confirmed'
  and (expires_at is null or expires_at > now())
order by patient_id, confirmed_at desc;

-- Atomically register an incoming encounter and idempotently claim one
-- inference request. Existing completed requests are returned without
-- rescoring; failed requests may be retried explicitly.
create or replace function public.claim_ml_inference_job(
  p_request_id text,
  p_patient_id uuid,
  p_pregnancy_episode_id uuid,
  p_encounter_id uuid,
  p_input_hash text,
  p_model_version text,
  p_requested_by uuid,
  p_request_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  existing public.ml_inference_jobs%rowtype;
  encounter_row public.encounters%rowtype;
  input_record jsonb;
  prediction_id uuid;
  claimed boolean := false;
begin
  input_record := p_request_payload #> '{records,0}';
  if jsonb_typeof(input_record) <> 'object' then
    raise exception 'ml_request_record_invalid';
  end if;

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
      and access.user_id = p_requested_by
      and access.relationship = 'assigned_bidan'
  ) then
    raise exception 'patient_access_denied';
  end if;

  -- Serialize requests touching the same encounter or idempotency key before
  -- their select/insert branches.
  perform pg_advisory_xact_lock(hashtextextended(p_encounter_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id, 0));

  select * into encounter_row
  from public.encounters
  where id = p_encounter_id
  for update;

  if found then
    if encounter_row.patient_id <> p_patient_id
       or encounter_row.pregnancy_episode_id <> p_pregnancy_episode_id then
      raise exception 'encounter_correlation_mismatch';
    end if;
    if encounter_row.input_hash is not null
       and encounter_row.input_hash <> p_input_hash then
      raise exception 'encounter_input_conflict';
    end if;
    if encounter_row.input_hash is null then
      update public.encounters
      set input_snapshot = input_record,
          input_hash = p_input_hash
      where id = p_encounter_id;
    end if;
  else
    insert into public.encounters (
      id,
      patient_id,
      pregnancy_episode_id,
      entered_by,
      source_type,
      verification_status,
      input_snapshot,
      input_hash
    ) values (
      p_encounter_id,
      p_patient_id,
      p_pregnancy_episode_id,
      p_requested_by,
      'manual',
      'verified',
      input_record,
      p_input_hash
    );
  end if;

  select * into existing
  from public.ml_inference_jobs
  where request_id = p_request_id
  for update;

  if found then
    if existing.patient_id <> p_patient_id
       or existing.pregnancy_episode_id <> p_pregnancy_episode_id
       or existing.encounter_id <> p_encounter_id
       or existing.input_hash <> p_input_hash
       or existing.model_version <> p_model_version then
      raise exception 'request_id_conflict';
    end if;

    if existing.status = 'failed' then
      update public.ml_inference_jobs
      set status = 'running',
          attempt_count = attempt_count + 1,
          requested_by = p_requested_by,
          error_code = null,
          error_message = null,
          started_at = now(),
          completed_at = null
      where id = existing.id
      returning * into existing;
      claimed := true;
    end if;
  else
    insert into public.ml_inference_jobs (
      request_id,
      patient_id,
      pregnancy_episode_id,
      encounter_id,
      input_hash,
      model_version,
      schema_version,
      request_payload,
      requested_by,
      status,
      started_at
    ) values (
      p_request_id,
      p_patient_id,
      p_pregnancy_episode_id,
      p_encounter_id,
      p_input_hash,
      p_model_version,
      '1.0',
      p_request_payload,
      p_requested_by,
      'running',
      now()
    ) returning * into existing;
    claimed := true;
  end if;

  select prediction.id into prediction_id
  from public.ml_predictions prediction
  where prediction.job_id = existing.id;

  return jsonb_build_object(
    'job_id', existing.id,
    'request_id', existing.request_id,
    'status', existing.status,
    'claimed', claimed,
    'prediction_id', prediction_id,
    'model_response', existing.model_response
  );
end;
$$;

create or replace function public.complete_ml_inference_job(
  p_job_id uuid,
  p_completed_by uuid,
  p_model_response jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  job public.ml_inference_jobs%rowtype;
  prediction public.ml_predictions%rowtype;
  model jsonb;
  result jsonb;
begin
  select * into job
  from public.ml_inference_jobs
  where id = p_job_id
  for update;
  if not found then
    raise exception 'ml_job_not_found';
  end if;

  if job.status = 'completed' then
    select * into prediction
    from public.ml_predictions
    where job_id = job.id;
    return jsonb_build_object('job_id', job.id, 'prediction_id', prediction.id);
  end if;
  if job.status <> 'running' then
    raise exception 'ml_job_not_running';
  end if;
  if p_completed_by <> job.requested_by then
    raise exception 'ml_job_actor_mismatch';
  end if;
  if p_model_response ->> 'request_id' <> job.request_id then
    raise exception 'ml_response_request_mismatch';
  end if;

  model := p_model_response -> 'model';
  result := p_model_response -> 'results' -> 0;
  if model is null or result is null then
    raise exception 'ml_response_shape_invalid';
  end if;
  if model ->> 'model_version' <> job.model_version
     or result ->> 'record_id' <> job.encounter_id::text
     or coalesce((result ->> 'ranking_eligible')::boolean, true) <> false then
    raise exception 'ml_response_correlation_invalid';
  end if;

  insert into public.ml_predictions (
    job_id,
    patient_id,
    pregnancy_episode_id,
    encounter_id,
    request_id,
    record_id,
    input_hash,
    prediction_status,
    model_score,
    risk_signal,
    risk_band,
    ranking_eligible,
    score_comparable_within_artifact,
    ranking_blockers,
    measurement_timestamp,
    errors,
    warnings,
    model_version,
    artifact_sha256,
    algorithm,
    operating_threshold,
    score_definition,
    ranking_policy,
    generated_at,
    raw_response,
    clinical_review_still_required,
    cannot_rule_out_maternal_risk,
    may_not_downgrade_clinician_urgency,
    may_not_suppress_referral
  ) values (
    job.id,
    job.patient_id,
    job.pregnancy_episode_id,
    job.encounter_id,
    job.request_id,
    result ->> 'record_id',
    job.input_hash,
    result ->> 'status',
    nullif(result ->> 'model_score', '')::double precision,
    case when result -> 'risk_signal' = 'null'::jsonb
      then null else (result ->> 'risk_signal')::boolean end,
    result ->> 'risk_band',
    (result ->> 'ranking_eligible')::boolean,
    (result ->> 'score_comparable_within_artifact')::boolean,
    result -> 'ranking_blockers',
    nullif(result ->> 'measurement_timestamp', '')::timestamptz,
    result -> 'errors',
    result -> 'warnings',
    model ->> 'model_version',
    model ->> 'artifact_sha256',
    model ->> 'algorithm',
    (model ->> 'operating_threshold')::double precision,
    model ->> 'score_definition',
    model ->> 'ranking_policy',
    (p_model_response ->> 'generated_at_utc')::timestamptz,
    p_model_response,
    (result ->> 'clinical_review_still_required')::boolean,
    (result ->> 'cannot_rule_out_maternal_risk')::boolean,
    (result ->> 'may_not_downgrade_clinician_urgency')::boolean,
    (result ->> 'may_not_suppress_referral')::boolean
  ) returning * into prediction;

  update public.ml_inference_jobs
  set status = 'completed',
      model_response = p_model_response,
      completed_at = now(),
      error_code = null,
      error_message = null
  where id = job.id;

  update public.encounters
  set observed_at = coalesce(
    observed_at,
    nullif(result ->> 'measurement_timestamp', '')::timestamptz
  )
  where id = job.encounter_id;

  return jsonb_build_object('job_id', job.id, 'prediction_id', prediction.id);
end;
$$;

create or replace function public.fail_ml_inference_job(
  p_job_id uuid,
  p_error_code text,
  p_error_message text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.ml_inference_jobs
  set status = 'failed',
      error_code = left(p_error_code, 100),
      error_message = left(p_error_message, 500),
      completed_at = now()
  where id = p_job_id and status <> 'completed';

  return jsonb_build_object('job_id', p_job_id, 'status', 'failed');
end;
$$;

revoke all on function public.claim_ml_inference_job(
  text, uuid, uuid, uuid, text, text, uuid, jsonb
) from public, anon, authenticated;
revoke all on function public.complete_ml_inference_job(uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.fail_ml_inference_job(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.claim_ml_inference_job(
  text, uuid, uuid, uuid, text, text, uuid, jsonb
) to service_role;
grant execute on function public.complete_ml_inference_job(uuid, uuid, jsonb)
  to service_role;
grant execute on function public.fail_ml_inference_job(uuid, text, text)
  to service_role;

do $$
declare
  table_name text;
begin
  foreach table_name in array array['ml_predictions', 'priority_snapshots']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$$;

comment on table public.ml_predictions is
  'Raw shadow-model output. Never use directly as the confirmed operational queue.';
comment on table public.priority_snapshots is
  'Governed rules plus optional ML proposal and explicit bidan confirmation.';
