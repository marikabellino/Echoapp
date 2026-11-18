-- ============================================================
-- mingle. — Privacy dei drop e drop agganciati agli eventi
-- Esegui nel SQL Editor di Supabase dopo 030
-- ============================================================
--
-- Cosa sistema:
--  1. Un drop di un evento FINITO non deve più essere pubblico, anche se
--     l'autore non riapre mai l'app. Prima il "declassamento" a cerchia
--     scattava solo sui drop di chi stava usando l'app in quel momento.
--     Ora: (a) la regola di lettura tratta da subito questi drop come
--     "cerchia", (b) il declassamento aggiorna i drop di tutti.
--  2. Un drop si può agganciare solo a un evento IN CORSO (né finito né
--     non ancora iniziato), e nasce pubblico come previsto dall'app.
--  3. "Solo io" vuol dire solo io: niente tag sui drop privati, e se un drop
--     diventa privato i tag esistenti vengono rimossi.
--  4. Limite di 500 caratteri sul testo anche lato database.

-- ─── 1a. Lettura: evento finito ⇒ il drop conta come "cerchia" ───────────────

create or replace function public.event_has_ended(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_event_id is not null and exists (
    select 1 from public.events e
    where e.id = p_event_id and e.ends_at < now()
  );
$$;

grant execute on function public.event_has_ended(uuid) to authenticated, anon;

drop policy if exists "Memories: read" on public.memories;

create policy "Memories: read"
  on public.memories for select
  using (
    auth.uid() = user_id
    or (
      not public.is_blocked_pair(user_id)
      and (
        -- Pubblico, tranne i drop di eventi già finiti
        (visibility = 'public' and not public.event_has_ended(event_id))
        -- Cerchia (inclusi i drop "pubblici" di eventi finiti)
        or (
          (visibility = 'circle'
            or (visibility = 'public' and public.event_has_ended(event_id)))
          and exists (
            select 1 from public.connections c
            where c.status = 'accepted'
              and (
                (c.requester_id = auth.uid() and c.target_id = memories.user_id)
                or (c.target_id = auth.uid() and c.requester_id = memories.user_id)
              )
          )
        )
        -- Taggati: mai sui drop privati
        or (
          visibility <> 'private'
          and exists (
            select 1 from public.drop_tags t
            where t.drop_id = memories.id and t.tagged_user_id = auth.uid()
          )
        )
      )
    )
  );

-- ─── 1b. Declassamento per tutti, non solo per l'utente corrente ─────────────

create or replace function public.downgrade_expired_event_drops()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.memories m
  set visibility = 'circle'
  where m.visibility = 'public'
    and m.event_id is not null
    and exists (
      select 1 from public.events e
      where e.id = m.event_id and e.ends_at < now()
    );
$$;

grant execute on function public.downgrade_expired_event_drops() to authenticated;

-- ─── 2. Agganciare un drop solo a un evento in corso ─────────────────────────

create or replace function public.check_memory_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.event_id is null then
    return new;
  end if;

  -- In update controlliamo solo se l'evento viene cambiato: il declassamento
  -- a "cerchia" di un drop di evento finito deve continuare a funzionare.
  if tg_op = 'UPDATE' and new.event_id is not distinct from old.event_id then
    return new;
  end if;

  if not exists (
    select 1 from public.events e
    where e.id = new.event_id
      and now() >= e.starts_at
      and now() <= e.ends_at
  ) then
    raise exception 'event_not_live'
      using hint = 'Si possono aggiungere drop solo a un evento in corso.';
  end if;

  if tg_op = 'INSERT' then
    new.visibility := 'public';
  end if;
  return new;
end;
$$;

drop trigger if exists memories_check_event on public.memories;
create trigger memories_check_event
  before insert or update of event_id on public.memories
  for each row execute function public.check_memory_event();

-- ─── 3. Niente tag sui drop privati ──────────────────────────────────────────

drop function if exists public.tag_users_on_drop(uuid, uuid[]);

create function public.tag_users_on_drop(p_drop_id uuid, p_user_ids uuid[])
returns table (tagged_user_id uuid)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_visibility text;
begin
  select m.visibility into v_visibility
  from public.memories m
  where m.id = p_drop_id and m.user_id = auth.uid();

  if not found then
    raise exception 'not_owner';
  end if;

  -- "Solo io" vuol dire solo io: nessun tag.
  if v_visibility = 'private' then
    return;
  end if;

  return query
  insert into public.drop_tags (drop_id, tagged_user_id, tagged_by)
  select p_drop_id, u, auth.uid()
  from unnest(p_user_ids) as u
  where u != auth.uid()
    and exists (
      select 1 from public.connections c
      where c.status = 'accepted'
        and (
          (c.requester_id = auth.uid() and c.target_id = u)
          or (c.target_id = auth.uid() and c.requester_id = u)
        )
    )
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = u)
         or (b.blocker_id = u and b.blocked_id = auth.uid())
    )
  on conflict (drop_id, tagged_user_id) do nothing
  returning drop_tags.tagged_user_id;
end;
$$;

grant execute on function public.tag_users_on_drop(uuid, uuid[]) to authenticated;

-- Se un drop diventa privato, i tag esistenti spariscono.
create or replace function public.clear_tags_on_private()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.visibility = 'private' and old.visibility is distinct from 'private' then
    delete from public.drop_tags where drop_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists memories_clear_tags_on_private on public.memories;
create trigger memories_clear_tags_on_private
  after update of visibility on public.memories
  for each row execute function public.clear_tags_on_private();

-- Pulizia una tantum: tag già presenti su drop privati.
delete from public.drop_tags t
using public.memories m
where m.id = t.drop_id and m.visibility = 'private';

-- ─── 4. Limite di lunghezza del testo ────────────────────────────────────────

alter table public.memories drop constraint if exists memories_description_length;
alter table public.memories
  add constraint memories_description_length
  check (char_length(description) <= 500) not valid;

-- ─── 5. "Taggato in" con le stesse regole di lettura ─────────────────────────
-- Allineata a "Memories: read": rispetta i blocchi, gli eventi finiti e i
-- drop privati (prima un bloccato poteva vedere i drop in cui eri taggato).

create or replace function public.get_tagged_drops(p_user_id uuid)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(m.*)
      || jsonb_build_object(
           'profiles', jsonb_build_object(
             'id', p.id,
             'username', p.username,
             'display_name', p.display_name,
             'avatar_url', p.avatar_url,
             'memories_count', p.memories_count,
             'connections_count', p.connections_count
           ),
           'event', case when e.id is null then null
                         else jsonb_build_object('id', e.id, 'title', e.title) end
         )
  from public.drop_tags t
  join public.memories m on m.id = t.drop_id
  join public.profiles p on p.id = m.user_id
  left join public.events e on e.id = m.event_id
  where t.tagged_user_id = p_user_id
    and t.hidden_by_tagged = false
    and m.visibility <> 'private'
    and (
      m.user_id = auth.uid()
      or (
        not public.is_blocked_pair(m.user_id)
        and not public.is_blocked_pair(p_user_id)
        and (
          (m.visibility = 'public' and not public.event_has_ended(m.event_id))
          or (
            (m.visibility = 'circle'
              or (m.visibility = 'public' and public.event_has_ended(m.event_id)))
            and exists (
              select 1 from public.connections c
              where c.status = 'accepted'
                and (
                  (c.requester_id = auth.uid() and c.target_id = m.user_id)
                  or (c.target_id = auth.uid() and c.requester_id = m.user_id)
                )
            )
          )
          or t.tagged_user_id = auth.uid()
        )
      )
    )
  order by t.created_at desc;
$$;

grant execute on function public.get_tagged_drops(uuid) to authenticated;
