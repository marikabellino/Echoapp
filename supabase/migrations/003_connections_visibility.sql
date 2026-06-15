-- ============================================================
-- Echo App — Connessioni tra utenti + visibilità ricordi
-- Esegui nel SQL Editor di Supabase
-- ============================================================

-- ─── Tabella connections ──────────────────────────────────────────────────────

create table if not exists public.connections (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid references public.profiles(id) on delete cascade not null,
  target_id    uuid references public.profiles(id) on delete cascade not null,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  unique (requester_id, target_id)
);

create index if not exists connections_requester_idx on public.connections (requester_id);
create index if not exists connections_target_idx    on public.connections (target_id);

alter table public.connections enable row level security;

create policy "Connections: read own"
  on public.connections for select
  using (auth.uid() = requester_id or auth.uid() = target_id);

create policy "Connections: send request"
  on public.connections for insert
  with check (auth.uid() = requester_id and auth.uid() != target_id);

create policy "Connections: accept by target"
  on public.connections for update
  using (auth.uid() = target_id);

create policy "Connections: delete own"
  on public.connections for delete
  using (auth.uid() = requester_id or auth.uid() = target_id);

-- ─── Colonna visibility su memories ──────────────────────────────────────────

alter table public.memories
  add column if not exists visibility text not null default 'public'
  check (visibility in ('public', 'circle', 'private'));

create index if not exists memories_visibility_idx on public.memories (visibility);

-- ─── Aggiorna RLS memories per supportare circle ──────────────────────────────

drop policy if exists "Memories: public read" on public.memories;

create policy "Memories: read"
  on public.memories for select
  using (
    auth.uid() = user_id
    or visibility = 'public'
    or (
      visibility = 'circle'
      and exists (
        select 1 from public.connections c
        where c.status = 'accepted'
          and (
            (c.requester_id = auth.uid() and c.target_id = memories.user_id)
            or (c.target_id = auth.uid() and c.requester_id = memories.user_id)
          )
      )
    )
  );

-- ─── RPC: get_connection_status ───────────────────────────────────────────────

create or replace function public.get_connection_status(target_user_id uuid)
returns text
language sql stable security definer as $$
  select case
    when exists (
      select 1 from public.connections
      where status = 'accepted'
        and (
          (requester_id = auth.uid() and target_id = target_user_id)
          or (requester_id = target_user_id and target_id = auth.uid())
        )
    ) then 'connected'
    when exists (
      select 1 from public.connections
      where requester_id = auth.uid()
        and target_id = target_user_id
        and status = 'pending'
    ) then 'pending_sent'
    when exists (
      select 1 from public.connections
      where requester_id = target_user_id
        and target_id = auth.uid()
        and status = 'pending'
    ) then 'pending_received'
    else 'none'
  end;
$$;
