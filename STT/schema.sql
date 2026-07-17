-- Hapus tabel jika sudah ada (Opsional untuk reset)
-- drop table if exists rekam_medis;

-- Buat tabel rekam_medis untuk menampung hasil ekstraksi AI
create table rekam_medis (
  id uuid primary key,
  measured_at timestamptz not null default now(),
  teks_mentah text,
  age_years integer default 0,
  systolic_bp integer default 0,
  diastolic_bp integer default 0,
  blood_sugar_value integer default 0,
  blood_sugar_unit text default 'mg/dL',
  body_temperature_value decimal(4,2) default 0.0,
  body_temperature_unit text default '°C',
  bmi decimal(4,2) default 0.0,
  mental_health text default 'Normal',
  heart_rate integer default 0,
  previous_complications boolean default false,
  preexisting_diabetes boolean default false,
  gestational_diabetes boolean default false
);

-- Buat index untuk optimasi pencarian berdasarkan waktu pengukuran (Opsional)
create index idx_rekam_medis_measured_at on rekam_medis(measured_at desc);