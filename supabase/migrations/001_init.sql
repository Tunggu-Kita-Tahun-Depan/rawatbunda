-- RawatBunda hackathon schema. All seeded records are synthetic.
-- Roles are read from auth.users.raw_app_meta_data.app_role and must be one
-- of: bidan, pasien, admin. Never set roles from Flutter or expose a
-- service-role key to the client.

create extension if not exists pgcrypto;

create table if not exists public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  distance_km numeric not null,
  has_ponek boolean not null default false,
  status text not null default 'available'
    check (status in ('available', 'full')),
  estimated_travel_minutes integer,
  status_source text not null default 'Data simulasi',
  status_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.referral_cases (
  id uuid primary key default gen_random_uuid(),
  patient_name text not null default '',
  gestational_age_weeks integer,
  systolic integer,
  diastolic integer,
  severe_headache boolean not null default false,
  visual_disturbance boolean not null default false,
  urgency text not null default 'routine',
  facility_name text,
  facility_distance_km numeric,
  step text not null default 'draft',
  sent_at timestamptz,
  contact_events jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Make this migration safe to apply to an older demo table.
alter table public.facilities
  add column if not exists estimated_travel_minutes integer,
  add column if not exists status_source text not null default 'Data simulasi',
  add column if not exists status_updated_at timestamptz not null default now();

alter table public.referral_cases
  add column if not exists contact_events jsonb not null default '[]'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

insert into public.facilities
  (name, distance_km, has_ponek, status, estimated_travel_minutes, status_source)
values
  ('Puskesmas Sukamaju', 2.1, false, 'available', 8, 'Simulasi admin'),
  ('RSUD Kartini', 6.4, true, 'available', 18, 'Simulasi admin'),
  ('RS Bersalin Harapan Bunda', 9.8, true, 'full', 26, 'Simulasi admin'),
  ('RSIA Sejahtera', 12.6, true, 'available', 31, 'Simulasi admin')
on conflict (name) do update set
  distance_km = excluded.distance_km,
  has_ponek = excluded.has_ponek,
  status = excluded.status,
  estimated_travel_minutes = excluded.estimated_travel_minutes,
  status_source = excluded.status_source,
  status_updated_at = now();

alter table public.facilities enable row level security;
alter table public.referral_cases enable row level security;

drop policy if exists facilities_select_authenticated on public.facilities;
create policy facilities_select_authenticated
  on public.facilities for select
  to authenticated
  using (true);

drop policy if exists facilities_admin_insert on public.facilities;
create policy facilities_admin_insert
  on public.facilities for insert
  to authenticated
  with check (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'admin'
  );

drop policy if exists facilities_admin_update on public.facilities;
create policy facilities_admin_update
  on public.facilities for update
  to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'admin'
  )
  with check (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'admin'
  );

drop policy if exists referral_bidan_select on public.referral_cases;
create policy referral_bidan_select
  on public.referral_cases for select
  to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'bidan'
  );

drop policy if exists referral_bidan_insert on public.referral_cases;
create policy referral_bidan_insert
  on public.referral_cases for insert
  to authenticated
  with check (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'bidan'
  );

drop policy if exists referral_bidan_update on public.referral_cases;
create policy referral_bidan_update
  on public.referral_cases for update
  to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'bidan'
  )
  with check (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'app_role', '') = 'bidan'
  );

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'referral_cases'
  ) then
    alter publication supabase_realtime add table public.referral_cases;
  end if;
end
$$;

-- Example role assignment to run manually in the Supabase SQL editor:
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
--   || '{"app_role":"bidan"}'::jsonb
-- where email = 'bidan@demo.id';
