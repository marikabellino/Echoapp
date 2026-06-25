-- ============================================================
-- Echo App — Utenti bloccati
-- Esegui nel SQL Editor di Supabase dopo 006
-- ============================================================

-- ─── Tabella blocked_users ────────────────────────────────────────────────────

create table if not exists public.blocked_users (
  id          uuid primary key default gen_random_uuid(),
  blocker_id  uuid references public.profiles(id) on delete cascade not null,
  blocked_id  uuid references public.profiles(id) on delete cascade not null,
  created_at  timestamptz not null default now(),
  unique (blocker_id, blocked_id)
);

create index if not exists blocked_users_blocker_idx on public.blocked_users (blocker_id);
create index if not exists blocked_users_blocked_idx on public.blocked_users (blocked_id);

alter table public.blocked_users enable row level security;

-- Solo il blocker può vedere i propri blocchi
create policy "BlockedUsers: select own"
  on public.blocked_users for select
  using (auth.uid() = blocker_id);

-- Solo l'utente autenticato può bloccare qualcuno
create policy "BlockedUsers: insert own"
  on public.blocked_users for insert
  with check (auth.uid() = blocker_id and auth.uid() != blocked_id);

-- Solo il blocker può sbloccare
create policy "BlockedUsers: delete own"
  on public.blocked_users for delete
  using (auth.uid() = blocker_id);

-- ─── Aggiorna search_users_nearby per escludere utenti bloccati ───────────────
-- DROP necessario perché la firma potrebbe differire da versioni precedenti.

drop function if exists public.search_users_nearby(text, double precision, double precision, integer, integer);

create or replace function public.search_users_nearby(
  search_query  text             default '',
  user_lat      double precision default null,
  user_lng      double precision default null,
  page_size     integer          default 20,
  page_offset   integer          default 0
)
returns table (
  id                uuid,
  username          text,
  display_name      text,
  bio               text,
  avatar_url        text,
  memories_count    integer,
  connections_count integer,
  created_at        timestamptz,
  distance_km       double precision
)
language sql stable security definer as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.bio,
    p.avatar_url,
    p.memories_count,
    p.connections_count,
    p.created_at,
    case
      when p.last_latitude  is not null
       and p.last_longitude is not null
       and user_lat         is not null
       and user_lng         is not null
      then round((
        6371.0 * acos(
          least(1.0, greatest(-1.0,
            cos(radians(user_lat)) * cos(radians(p.last_latitude))
            * cos(radians(p.last_longitude) - radians(user_lng))
            + sin(radians(user_lat)) * sin(radians(p.last_latitude))
          ))
        )
      )::numeric, 1)::double precision
      else null
    end as distance_km
  from public.profiles p
  where p.id != auth.uid()
    -- Escludi utenti che io ho bloccato
    and not exists (
      select 1 from public.blocked_users b
      where b.blocker_id = auth.uid() and b.blocked_id = p.id
    )
    -- Escludi utenti che mi hanno bloccato
    and not exists (
      select 1 from public.blocked_users b
      where b.blocker_id = p.id and b.blocked_id = auth.uid()
    )
    and (
      search_query = ''
      or search_query is null
      or p.username     ilike '%' || search_query || '%'
      or p.display_name ilike '%' || search_query || '%'
    )
  order by
    case
      when p.last_latitude  is not null
       and p.last_longitude is not null
       and user_lat         is not null
       and user_lng         is not null
      then 6371.0 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(user_lat)) * cos(radians(p.last_latitude))
          * cos(radians(p.last_longitude) - radians(user_lng))
          + sin(radians(user_lat)) * sin(radians(p.last_latitude))
        ))
      )
      else 999999.0
    end asc,
    p.memories_count desc
  limit page_size
  offset page_offset;
$$;

-- ─── Aggiorna get_my_connections per escludere bloccati ───────────────────────

create or replace function public.get_my_connections()
returns table (
  id                uuid,
  username          text,
  display_name      text,
  bio               text,
  avatar_url        text,
  memories_count    integer,
  connections_count integer,
  created_at        timestamptz,
  distance_km       double precision
)
language sql stable security definer as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.bio,
    p.avatar_url,
    p.memories_count,
    p.connections_count,
    p.created_at,
    null::double precision as distance_km
  from public.profiles p
  inner join public.connections c
    on (c.requester_id = auth.uid() and c.target_id = p.id)
    or (c.target_id = auth.uid() and c.requester_id = p.id)
  where c.status = 'accepted'
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by coalesce(nullif(p.display_name, ''), p.username);
$$;

-- ─── Aggiorna get_pending_requests per escludere bloccati ────────────────────

create or replace function public.get_pending_requests()
returns table (
  id                uuid,
  username          text,
  display_name      text,
  bio               text,
  avatar_url        text,
  memories_count    integer,
  connections_count integer,
  created_at        timestamptz,
  distance_km       double precision
)
language sql stable security definer as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.bio,
    p.avatar_url,
    p.memories_count,
    p.connections_count,
    p.created_at,
    null::double precision as distance_km
  from public.profiles p
  inner join public.connections c on c.requester_id = p.id
  where c.target_id = auth.uid()
    and c.status = 'pending'
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by c.created_at desc;
$$;
