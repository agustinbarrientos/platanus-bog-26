-- Moirai schema. Run in the Supabase SQL editor, or apply with scripts/apply_schema.py.
--
-- RLS is enabled with no policies on every table. The backend connects as
-- `postgres`, which bypasses RLS, so this does not restrict the API — it closes
-- the *other* door: anything in the `public` schema is also published by
-- Supabase's PostgREST endpoint and reachable with the anon key. Enabled with
-- no policies means that path denies everything. Since these tables hold health
-- data, leaving it off would put it on the open internet.
--
-- Because RLS is not what protects the API, every query in the application must
-- filter by user_id itself. That is the actual access control.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
    -- Deleting the auth user deletes their health data. That is the behaviour
    -- you want to be automatic rather than remembered.
    user_id       uuid primary key references auth.users (id) on delete cascade,

    full_name     varchar(120),
    date_of_birth date,
    height_cm     numeric(5,1),
    weight_kg     numeric(5,1),
    blood_type    varchar(3),
    sex_at_birth  varchar(10),

    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),

    -- Every column is nullable: the form is answered one question at a time and
    -- a half-filled profile is a normal state. The CHECKs still reject nonsense
    -- when a value *is* present, because a twin fed a 700 kg weight does not
    -- error, it produces a confident and wrong survival curve.
    constraint profiles_sex_at_birth_valid
        check (sex_at_birth is null or sex_at_birth in ('female','male','intersex')),
    constraint profiles_blood_type_valid
        check (blood_type is null or blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    constraint profiles_height_plausible
        check (height_cm is null or height_cm between 100 and 250),
    constraint profiles_weight_plausible
        check (weight_kg is null or weight_kg between 25 and 350),
    constraint profiles_dob_in_past
        check (date_of_birth is null or date_of_birth < current_date)
);

alter table public.profiles enable row level security;

-- Keeps updated_at honest without the application having to remember.
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
    before update on public.profiles
    for each row execute function public.touch_updated_at();
