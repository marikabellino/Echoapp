revoke select on public.profiles from anon, authenticated;
grant select (
  id,
  username,
  display_name,
  bio,
  avatar_url,
  memories_count,
  connections_count,
  created_at,
  updated_at,
  username_changed_at
) on public.profiles to anon, authenticated;

revoke update on public.profiles from anon, authenticated;
grant update (
  username,
  display_name,
  bio,
  avatar_url,
  fcm_token,
  updated_at
) on public.profiles to authenticated;

create or replace function public.update_user_location(
  lat double precision,
  lng double precision
)
returns void
language sql volatile security definer as $$
  update public.profiles
  set last_latitude       = case when share_distance then round(lat::numeric, 2)::double precision end,
      last_longitude      = case when share_distance then round(lng::numeric, 2)::double precision end,
      location_updated_at = case when share_distance then now() end
  where id = auth.uid();
$$;

create or replace function public.set_share_distance(enabled boolean)
returns void
language sql volatile security definer as $$
  update public.profiles
  set share_distance      = enabled,
      last_latitude       = case when enabled then last_latitude end,
      last_longitude      = case when enabled then last_longitude end,
      location_updated_at = case when enabled then location_updated_at end,
      updated_at          = now()
  where id = auth.uid();
$$;

update public.profiles
set last_latitude = null,
    last_longitude = null,
    location_updated_at = null
where not share_distance;

update public.profiles
set last_latitude  = round(last_latitude::numeric, 2)::double precision,
    last_longitude = round(last_longitude::numeric, 2)::double precision
where last_latitude is not null;

create or replace function public.get_circle_nearby(
  user_lat double precision,
  user_lng double precision
)
returns table (
  id                  uuid,
  username            text,
  display_name        text,
  avatar_url          text,
  created_at          timestamptz,
  distance_km         double precision,
  location_updated_at timestamptz
)
language sql stable security definer as $$
  with me as (
    select share_distance, last_latitude as lat, last_longitude as lng
    from public.profiles
    where id = auth.uid()
  )
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.created_at,
    case
      when p.share_distance
       and me.share_distance
       and me.lat is not null
       and p.last_latitude is not null
       and p.location_updated_at > now() - interval '6 hours'
      then round(
        6371.0 * acos(
          least(1.0, greatest(-1.0,
            cos(radians(me.lat)) * cos(radians(p.last_latitude))
            * cos(radians(p.last_longitude) - radians(me.lng))
            + sin(radians(me.lat)) * sin(radians(p.last_latitude))
          ))
        )
      )::double precision
      else null
    end as distance_km,
    null::timestamptz as location_updated_at
  from public.profiles p
  cross join me
  inner join public.connections c
    on (c.requester_id = auth.uid() and c.target_id = p.id)
    or (c.target_id = auth.uid() and c.requester_id = p.id)
  where c.status = 'accepted'
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by distance_km asc nulls last,
           coalesce(nullif(p.display_name, ''), p.username);
$$;

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
    null::double precision as distance_km
  from public.profiles p
  where p.id != auth.uid()
    and auth.uid() is not null
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
    and (
      search_query = ''
      or search_query is null
      or p.username     ilike '%' || search_query || '%'
      or p.display_name ilike '%' || search_query || '%'
    )
  order by
    case when p.username ilike search_query || '%' then 0 else 1 end,
    p.memories_count desc,
    p.username
  limit least(page_size, 50)
  offset page_offset;
$$;

drop policy if exists "Comments: public read" on public.comments;
create policy "Comments: read if drop visible"
  on public.comments for select
  using (exists (select 1 from public.memories m where m.id = memory_id));

drop policy if exists "Likes: public read" on public.likes;
create policy "Likes: read if drop visible"
  on public.likes for select
  using (exists (select 1 from public.memories m where m.id = memory_id));

drop policy if exists "Storage memories: public read" on storage.objects;
drop policy if exists "Storage avatars: public read" on storage.objects;
drop policy if exists "Storage memories: owner read" on storage.objects;
drop policy if exists "Storage avatars: owner read" on storage.objects;

create policy "Storage memories: owner read"
  on storage.objects for select
  using (bucket_id = 'memories' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Storage avatars: owner read"
  on storage.objects for select
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "Storage memories: auth upload" on storage.objects;
create policy "Storage memories: auth upload"
  on storage.objects for insert
  with check (bucket_id = 'memories' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "Storage avatars: auth upload" on storage.objects;
create policy "Storage avatars: auth upload"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

alter table public.reports
  add column if not exists comment_id uuid references public.comments(id) on delete cascade;

alter table public.reports drop constraint if exists reports_target_check;
alter table public.reports
  add constraint reports_target_check
  check (num_nonnulls(memory_id, reported_user_id, comment_id) = 1);

alter table public.reports drop constraint if exists reports_reporter_comment_unique;
alter table public.reports
  add constraint reports_reporter_comment_unique
  unique (reporter_id, comment_id);
