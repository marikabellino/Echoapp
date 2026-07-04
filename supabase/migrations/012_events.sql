-- ============================================================
-- Echo App — Eventi (locali partner) + collegamento ai drop
-- Esegui nel SQL Editor del tuo progetto Supabase
-- ============================================================

-- ─── Events ──────────────────────────────────────────────────────────────────
-- Curati manualmente (dashboard/service role) — nessuna policy di insert
-- per i client in questa v1.

create table if not exists public.events (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  venue_name      text not null,
  city            text not null,
  latitude        double precision not null,
  longitude       double precision not null,
  radius_meters   double precision not null default 20000,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  cover_image_url text,
  description     text not null default '',
  created_at      timestamptz not null default now()
);

create index if not exists events_starts_idx on public.events (starts_at);
create index if not exists events_ends_idx   on public.events (ends_at);

alter table public.events enable row level security;

create policy "Events: public read"
  on public.events for select using (true);

-- ─── Collegamento evento sui drop ─────────────────────────────────────────────

alter table public.memories
  add column if not exists event_id uuid references public.events(id) on delete set null;

create index if not exists memories_event_idx on public.memories (event_id);
