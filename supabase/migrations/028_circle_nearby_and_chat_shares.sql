alter table public.profiles
  add column if not exists location_updated_at timestamptz,
  add column if not exists share_distance boolean not null default false;

create or replace function public.set_share_distance(enabled boolean)
returns void
language sql volatile security definer as $$
  update public.profiles
  set share_distance = enabled,
      updated_at     = now()
  where id = auth.uid();
$$;

create or replace function public.get_my_share_distance()
returns boolean
language sql stable security definer as $$
  select coalesce(
    (select share_distance from public.profiles where id = auth.uid()),
    false
  );
$$;

create or replace function public.update_user_location(
  lat double precision,
  lng double precision
)
returns void
language sql volatile security definer as $$
  update public.profiles
  set last_latitude       = lat,
      last_longitude      = lng,
      location_updated_at = now(),
      updated_at          = now()
  where id = auth.uid();
$$;

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
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.created_at,
    case
      when p.last_latitude  is not null
       and p.last_longitude is not null
       and user_lat         is not null
       and user_lng         is not null
       and p.location_updated_at > now() - interval '6 hours'
       and p.share_distance
       and (select me.share_distance from public.profiles me where me.id = auth.uid())
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
    end as distance_km,
    p.location_updated_at
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
  order by distance_km asc nulls last,
           coalesce(nullif(p.display_name, ''), p.username);
$$;

grant execute on function public.get_circle_nearby(double precision, double precision)
  to authenticated;

grant execute on function public.set_share_distance(boolean) to authenticated;
grant execute on function public.get_my_share_distance() to authenticated;

alter table public.messages
  add column if not exists shared_drop_id uuid references public.memories(id) on delete set null,
  add column if not exists location_lat   double precision,
  add column if not exists location_lng   double precision,
  add column if not exists location_label text;

drop function if exists public.get_conversations();

create function public.get_conversations()
returns table (
  conversation_id      uuid,
  other_user_id        uuid,
  other_username       text,
  other_display_name   text,
  other_avatar_url     text,
  last_message         text,
  last_message_gif_url text,
  last_message_kind    text,
  last_message_at      timestamptz,
  unread_count         bigint
)
language sql
stable
security definer
as $$
  select
    c.id,
    case when c.user1_id = auth.uid() then c.user2_id else c.user1_id end,
    p.username,
    p.display_name,
    p.avatar_url,
    lm.content,
    lm.gif_url,
    case
      when lm.gif_url is not null        then 'gif'
      when lm.shared_drop_id is not null then 'drop'
      when lm.location_lat is not null   then 'location'
      else 'text'
    end,
    lm.created_at,
    coalesce((
      select count(*)
      from public.messages m2
      where m2.conversation_id = c.id
        and m2.sender_id != auth.uid()
        and m2.read_at is null
    ), 0)
  from public.conversations c
  join public.profiles p
    on p.id = case when c.user1_id = auth.uid() then c.user2_id else c.user1_id end
  left join lateral (
    select content, gif_url, shared_drop_id, location_lat, created_at
    from public.messages
    where conversation_id = c.id
    order by created_at desc
    limit 1
  ) lm on true
  where (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by lm.created_at desc nulls last;
$$;

grant execute on function public.get_conversations() to authenticated;
