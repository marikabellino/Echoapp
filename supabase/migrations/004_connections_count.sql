-- ============================================================
-- Echo App — Counter connessioni + lista cerchia/richieste
-- Esegui nel SQL Editor di Supabase dopo 003
-- ============================================================

-- ─── Colonna connections_count su profiles ────────────────────────────────────

alter table public.profiles
  add column if not exists connections_count integer not null default 0;

-- ─── Trigger: incrementa entrambi gli utenti quando la connessione viene accettata

create or replace function public.on_connection_accepted()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'accepted' and old.status = 'pending' then
    update public.profiles
    set connections_count = connections_count + 1
    where id in (new.requester_id, new.target_id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_connection_accepted on public.connections;
create trigger on_connection_accepted
  after update on public.connections
  for each row execute function public.on_connection_accepted();

-- ─── Trigger: decrementa entrambi quando una connessione accettata viene rimossa

create or replace function public.on_connection_deleted()
returns trigger language plpgsql security definer as $$
begin
  if old.status = 'accepted' then
    update public.profiles
    set connections_count = greatest(0, connections_count - 1)
    where id in (old.requester_id, old.target_id);
  end if;
  return old;
end;
$$;

drop trigger if exists on_connection_deleted on public.connections;
create trigger on_connection_deleted
  after delete on public.connections
  for each row execute function public.on_connection_deleted();

-- ─── RPC: get_my_connections ──────────────────────────────────────────────────
-- Restituisce i profili con cui l'utente ha una connessione accettata.

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
  order by coalesce(nullif(p.display_name, ''), p.username);
$$;

-- ─── RPC: get_pending_requests ────────────────────────────────────────────────
-- Restituisce i profili che hanno inviato una richiesta di connessione all'utente.

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
  order by c.created_at desc;
$$;

-- ─── Aggiorna search_users_nearby per includere connections_count ─────────────
-- DROP necessario perché il tipo di ritorno cambia (aggiunta colonna connections_count)

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
