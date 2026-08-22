-- Moirai schema. Run in the Supabase SQL editor, or apply with
-- scripts/apply_schema.py. Every statement is idempotent.
--
-- This service owns its accounts. Supabase is the Postgres host and nothing
-- more: `auth.users` is not referenced anywhere below, and Supabase Auth is
-- not part of the login flow.
--
-- RLS is enabled with no policies on every table. The backend connects as
-- `postgres`, which bypasses RLS, so this does not restrict the API — it
-- closes the *other* door: anything in the `public` schema is also published
-- by Supabase's PostgREST endpoint and reachable with the anon key. Enabled
-- with no policies means that path denies everything. These tables hold
-- password hashes and health data, so leaving it off would put both on the
-- open internet.
--
-- Because RLS is not what protects the API, every query in the application
-- must filter by user_id itself. That is the actual access control.

create extension if not exists "pgcrypto";


-- ---------------------------------------------------------------- accounts --

create table if not exists public.users (
    id            uuid primary key default gen_random_uuid(),

    -- Stored already lower-cased by the application, so this plain unique
    -- index is enough to stop two accounts differing only by capitalisation.
    email         varchar(320) not null unique,
    -- argon2id. Never leaves the database except to be verified against.
    password_hash varchar(255) not null,

    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    last_login_at timestamptz
);

alter table public.users enable row level security;


-- One row per signed-in device. Revoking a row signs that device out, and it
-- takes effect on the very next request because every request reads this table.
--
-- The token itself is never stored, only its SHA-256, so a database dump
-- yields nothing usable. It is also why the value is shown to the client
-- exactly once, at login: there is no way to look it up again.
create table if not exists public.auth_tokens (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references public.users (id) on delete cascade,
    token_hash varchar(64) not null unique,

    expires_at timestamptz not null,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    -- Only so a user could recognise their own devices in a future "signed in
    -- on these devices" screen. Never used for any decision.
    device     varchar(200)
);

create index if not exists auth_tokens_user_id_idx
    on public.auth_tokens (user_id);
-- Supports the sweep of dead rows on login.
create index if not exists auth_tokens_expires_at_idx
    on public.auth_tokens (expires_at);

alter table public.auth_tokens enable row level security;

-- Dropped rather than migrated: it belonged to the cookie/refresh-token design
-- that this replaced, and any row in it is a session that no longer resolves.
drop table if exists public.refresh_sessions;


-- ---------------------------------------------------------------- profiles --

create table if not exists public.profiles (
    -- Deleting the account deletes their health data. That is the behaviour
    -- you want to be automatic rather than remembered.
    user_id       uuid primary key references public.users (id) on delete cascade,

    full_name     varchar(120),
    date_of_birth date,
    height_cm     numeric(5,1),
    weight_kg     numeric(5,1),
    blood_type    varchar(3),
    sex_at_birth  varchar(10),

    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),

    -- Every column is nullable: the form is answered one question at a time
    -- and a half-filled profile is a normal state. The CHECKs still reject
    -- nonsense when a value *is* present, because a twin fed a 700 kg weight
    -- does not error, it produces a confident and wrong survival curve.
    constraint profiles_sex_at_birth_valid
        check (sex_at_birth is null or sex_at_birth in ('F','M')),
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

-- sex_at_birth narrowed from ('female','male','intersex') to ('F','M') — age
-- and sex now come from this column for the PhenoAge/Monte Carlo/chat
-- endpoints, which need a fixed two-bucket value to look up NHANES medians
-- by. Constraint dropped *before* the remap below — updating 'male' -> 'M'
-- while the old CHECK is still live rejects 'M' as an invalid value, since
-- the old constraint doesn't know about it yet. 'intersex' has no
-- equivalent bucket, so it clears to null rather than being force-mapped.
alter table public.profiles drop constraint if exists profiles_sex_at_birth_valid;

update public.profiles set sex_at_birth = 'F' where sex_at_birth = 'female';
update public.profiles set sex_at_birth = 'M' where sex_at_birth = 'male';
update public.profiles set sex_at_birth = null where sex_at_birth = 'intersex';

alter table public.profiles add constraint profiles_sex_at_birth_valid
    check (sex_at_birth is null or sex_at_birth in ('F','M'));


-- ------------------------------------------------------ health context --
--
-- The longevity/risk-assessment intake: demographics, biomarkers, habits,
-- family history and the caller's stated goals. JSONB rather than one column
-- per field or a child table per biomarker, because the shape underneath is
-- defined by whatever assessment produced it, not by this schema.

create table if not exists public.health_context (
    user_id              uuid primary key references public.users (id) on delete cascade,

    demografia           jsonb,
    biomarcadores        jsonb,
    habitos              jsonb,
    historia_familiar    jsonb,
    objetivos_usuario    jsonb,
    datos_faltantes      jsonb,
    notas_incertidumbre  text,
    suplementos          jsonb,
    -- Connection status only (provider + linked) -- the raw wearable data
    -- feed has nowhere to land yet, this is not that.
    wearable             jsonb,
    -- Set explicitly by the app when its onboarding flow finishes, not
    -- derived from field coverage -- some onboarding steps (photo, genetic
    -- test) aren't a stored field this schema can check for presence.
    onboarding_completo  boolean not null default false,

    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now()
);

-- Columns added after health_context already existed on some databases --
-- create table if not exists above is a no-op for an existing table, so an
-- already-provisioned database needs these added explicitly.
alter table public.health_context add column if not exists suplementos jsonb;
alter table public.health_context add column if not exists wearable jsonb;
alter table public.health_context add column if not exists onboarding_completo boolean not null default false;

alter table public.health_context enable row level security;


-- ------------------------------------------- migration off Supabase Auth --
--
-- Only does anything on a database created before this service owned its own
-- accounts, where profiles.user_id pointed at auth.users.
--
-- Note the DELETE. A profile whose user_id is not in public.users is an
-- orphan: the account it belonged to lives in a table this application no
-- longer reads, so the row is unreachable and the new foreign key cannot be
-- added while it exists. If that database holds profiles you care about,
-- migrate those accounts into public.users *before* running this file.

do $$
begin
    if exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_class r on r.oid = c.confrelid
        join pg_namespace rn on rn.oid = r.relnamespace
        where t.relname = 'profiles' and c.contype = 'f' and rn.nspname = 'auth'
    ) then
        alter table public.profiles drop constraint if exists profiles_user_id_fkey;

        delete from public.profiles p
        where not exists (select 1 from public.users u where u.id = p.user_id);

        alter table public.profiles
            add constraint profiles_user_id_fkey
            foreign key (user_id) references public.users (id) on delete cascade;

        raise notice 'profiles now references public.users';
    end if;
end
$$;


-- ----------------------------------------------------------------- upkeep --

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

drop trigger if exists users_touch_updated_at on public.users;
create trigger users_touch_updated_at
    before update on public.users
    for each row execute function public.touch_updated_at();

drop trigger if exists health_context_touch_updated_at on public.health_context;
create trigger health_context_touch_updated_at
    before update on public.health_context
    for each row execute function public.touch_updated_at();


-- Belt and braces alongside RLS: Supabase grants the anon and authenticated
-- roles access to the public schema by default, and the users table holds
-- password hashes. Wrapped because those roles do not exist outside Supabase.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on public.users, public.auth_tokens, public.profiles, public.health_context
            from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on public.users, public.auth_tokens, public.profiles, public.health_context
            from authenticated;
    end if;
end
$$;
