create table if not exists public.active_sessions (
  device_id text primary key,
  nickname text not null,
  status text not null check (status in ('running', 'paused')),
  task_title text,
  category_color text,
  started_at timestamptz,
  planned_minutes integer not null default 0,
  elapsed_seconds integer not null default 0,
  last_seen_at timestamptz not null default now()
);

alter table public.active_sessions enable row level security;

grant usage on schema public to anon;
grant select, insert, update, delete on public.active_sessions to anon;

drop policy if exists "Public active sessions are readable" on public.active_sessions;
create policy "Public active sessions are readable"
on public.active_sessions for select
to anon
using (true);

drop policy if exists "Anonymous devices can publish active sessions" on public.active_sessions;
create policy "Anonymous devices can publish active sessions"
on public.active_sessions for insert
to anon
with check (true);

drop policy if exists "Anonymous devices can refresh active sessions" on public.active_sessions;
create policy "Anonymous devices can refresh active sessions"
on public.active_sessions for update
to anon
using (true)
with check (true);

drop policy if exists "Anonymous devices can clear active sessions" on public.active_sessions;
create policy "Anonymous devices can clear active sessions"
on public.active_sessions for delete
to anon
using (true);

create index if not exists active_sessions_last_seen_at_idx
on public.active_sessions (last_seen_at desc);

create table if not exists public.public_session_summaries (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  nickname text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  elapsed_seconds integer not null check (elapsed_seconds > 0),
  task_title text,
  category_color text,
  rating_raw integer not null default 1,
  created_at timestamptz not null default now()
);

alter table public.public_session_summaries enable row level security;

grant select, insert on public.public_session_summaries to anon;

drop policy if exists "Public session summaries are readable" on public.public_session_summaries;
create policy "Public session summaries are readable"
on public.public_session_summaries for select
to anon
using (true);

drop policy if exists "Anonymous devices can publish session summaries" on public.public_session_summaries;
create policy "Anonymous devices can publish session summaries"
on public.public_session_summaries for insert
to anon
with check (true);

create index if not exists public_session_summaries_started_at_idx
on public.public_session_summaries (started_at desc);

create index if not exists public_session_summaries_device_started_idx
on public.public_session_summaries (device_id, started_at desc);
