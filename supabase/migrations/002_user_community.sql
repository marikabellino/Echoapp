-- ============================================================
-- Echo App — Community: ricerca utenti per prossimità
-- Esegui nel SQL Editor di Supabase
-- ============================================================

-- ─── Posizione dell'utente sul profilo ───────────────────────────────────────

alter table public.profiles
  add column if not exists last_latitude  double precision,
  add column if not exists last_longitude double precision;

-- ─── RPC: search_users_nearby ────────────────────────────────────────────────
-- Restituisce profili filtrati per username/display_name e ordinati per
-- distanza Haversine dall'utente corrente. Se le coordinate non sono
-- disponibili, ordina per memories_count desc.

create or replace function public.search_users_nearby(
  search_query  text             default '',
  user_lat      double precision default null,
  user_lng      double precision default null,
  page_size     integer          default 20,
  page_offset   integer          default 0
)
returns table (
  id             uuid,
  username       text,
  display_name   text,
  bio            text,
  avatar_url     text,
  memories_count integer,
  created_at     timestamptz,
  distance_km    double precision
)
language sql stable security definer as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.bio,
    p.avatar_url,
    p.memories_count,
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

-- ─── RPC: update_user_location ───────────────────────────────────────────────
-- Aggiorna la posizione dell'utente autenticato (chiamata silente dall'app).

create or replace function public.update_user_location(
  lat double precision,
  lng double precision
)
returns void
language sql volatile security definer as $$
  update public.profiles
  set last_latitude  = lat,
      last_longitude = lng,
      updated_at     = now()
  where id = auth.uid();
$$;
