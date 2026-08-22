-- Run this once in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- The backend connects as the `postgres` role through the pooler, which is a
-- superuser and therefore bypasses RLS entirely. RLS is still enabled below,
-- because anything in the `public` schema is also published by Supabase's
-- PostgREST API and reachable with the anon key. Enabled-with-no-policies means
-- that public route denies every request while the backend keeps full access.
-- Leaving it off would put this table on the open internet.

create extension if not exists "pgcrypto";

create table if not exists public.items (
    id          uuid primary key default gen_random_uuid(),
    name        varchar(200) not null,
    description varchar(2000),
    created_at  timestamptz not null default now()
);

create index if not exists items_created_at_idx on public.items (created_at desc);

alter table public.items enable row level security;
