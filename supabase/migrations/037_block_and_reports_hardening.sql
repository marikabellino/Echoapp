-- mingle. — Blocco utenti e segnalazioni: chiusura delle falle
--
-- Da eseguire dopo la 036.
--
--  1. Chi è bloccato non può più mandare richieste di cerchia a chi l'ha
--     bloccato (prima poteva, e a quella persona arrivava anche la notifica).
--  2. Bloccare chiude ogni contatto, direttamente nel database (prima lo
--     faceva solo l'app): esce dalla cerchia, le richieste in sospeso spariscono
--     e la chat si chiude. Se un giorno lo sblocchi, la chat non riparte da
--     sola: chi vuole riscrivere manda una nuova richiesta di messaggio.
--  3. Chi è bloccato ora "lo sa" nel modo giusto: il tuo profilo gli risulta
--     non disponibile (prima lo vedeva come se niente fosse).
--  4. L'elenco delle persone taggate in un drop non mostra chi ti ha bloccato
--     o hai bloccato, e rispetta i drop privati.
--  5. Una vista per leggere le segnalazioni dal pannello di Supabase.

-- ─── 1. Niente richieste di cerchia tra persone bloccate ─────────────────────

drop policy if exists "Connections: send request" on public.connections;
create policy "Connections: send request"
  on public.connections for insert
  with check (
    auth.uid() = requester_id
    and auth.uid() != target_id
    and not public.is_blocked_pair(target_id)
  );

drop policy if exists "Connections: accept by target" on public.connections;
create policy "Connections: accept by target"
  on public.connections for update
  using (auth.uid() = target_id and not public.is_blocked_pair(requester_id));

-- ─── 2. Bloccare chiude ogni contatto ────────────────────────────────────────

alter table public.conversations
  add column if not exists requested_at timestamptz;

create or replace function public.on_user_blocked()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- fuori dalla cerchia (in entrambe le direzioni) e niente richieste in sospeso
  delete from public.connections c
  where (c.requester_id = new.blocker_id and c.target_id = new.blocked_id)
     or (c.requester_id = new.blocked_id and c.target_id = new.blocker_id);

  -- richieste di messaggio non ancora accettate: via
  delete from public.conversations c
  where c.status = 'pending'
    and c.requested_by is not null
    and ((c.user1_id = new.blocker_id and c.user2_id = new.blocked_id)
      or (c.user1_id = new.blocked_id and c.user2_id = new.blocker_id));

  -- chat già aperte: si chiudono. La cronologia resta (serve anche per
  -- eventuali segnalazioni) ma nessuno dei due può scrivere finché non c'è
  -- una nuova richiesta accettata.
  update public.conversations c
  set status = 'pending', requested_by = null, requested_at = null
  where (c.user1_id = new.blocker_id and c.user2_id = new.blocked_id)
     or (c.user1_id = new.blocked_id and c.user2_id = new.blocker_id);

  return new;
end;
$$;

drop trigger if exists blocked_users_close_contacts on public.blocked_users;
create trigger blocked_users_close_contacts
  after insert on public.blocked_users
  for each row execute function public.on_user_blocked();

-- Messaggi: in una richiesta conta solo ciò che è stato scritto DOPO l'invio
-- della richiesta (una chat chiusa da un blocco può avere una cronologia).
create or replace function public.can_send_message(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
      and not public.is_blocked_pair(
        case when c.user1_id = auth.uid() then c.user2_id else c.user1_id end
      )
      and (
        public.are_connected(c.user1_id, c.user2_id)
        or (
          not public.is_minor(c.user1_id) and not public.is_minor(c.user2_id)
          and (
            c.status = 'accepted'
            or (c.status = 'pending'
                and c.requested_by = auth.uid()
                and not exists (
                  select 1 from public.messages m
                  where m.conversation_id = c.id
                    and m.sender_id = auth.uid()
                    and m.created_at >= coalesce(c.requested_at, '-infinity'::timestamptz)
                ))
          )
        )
      )
  );
$$;

create or replace function public.get_or_create_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conv_id   uuid;
  conv_req  uuid;
  conv_st   text;
  u1        uuid;
  u2        uuid;
  connected boolean;
begin
  if other_user_id = auth.uid() then
    raise exception 'self';
  end if;

  if public.is_blocked_pair(other_user_id) then
    raise exception 'blocked';
  end if;

  connected := public.are_connected(auth.uid(), other_user_id);

  if auth.uid() < other_user_id then
    u1 := auth.uid();
    u2 := other_user_id;
  else
    u1 := other_user_id;
    u2 := auth.uid();
  end if;

  select id, requested_by, status into conv_id, conv_req, conv_st
  from public.conversations
  where user1_id = u1 and user2_id = u2;

  if conv_id is not null then
    if connected then
      update public.conversations
      set status = 'accepted'
      where id = conv_id and status = 'pending';
    elsif conv_st = 'pending' and conv_req is null then
      -- chat chiusa da un blocco poi tolto: chi la riapre manda una nuova
      -- richiesta (con i minorenni no: solo cerchia)
      if public.is_minor(auth.uid()) or public.is_minor(other_user_id) then
        raise exception 'minor_circle_only';
      end if;
      update public.conversations
      set requested_by = auth.uid(), requested_at = now()
      where id = conv_id;
    end if;
    return conv_id;
  end if;

  if not connected
     and (public.is_minor(auth.uid()) or public.is_minor(other_user_id)) then
    raise exception 'minor_circle_only';
  end if;

  insert into public.conversations (user1_id, user2_id, status, requested_by, requested_at)
  values (
    u1, u2,
    case when connected then 'accepted' else 'pending' end,
    case when connected then null else auth.uid() end,
    case when connected then null else now() end
  )
  returning id into conv_id;

  return conv_id;
end;
$$;

-- Elenco chat: una richiesta compare a chi la riceve solo dopo che è
-- arrivato il messaggio; una chat chiusa da un blocco (e non riaperta) non
-- compare a nessuno dei due.
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
  unread_count         bigint,
  status               text,
  requested_by         uuid
)
language sql
stable
security definer
set search_path = public
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
    ), 0),
    case
      when c.status = 'pending' and public.are_connected(c.user1_id, c.user2_id)
        then 'accepted'
      else c.status
    end,
    c.requested_by
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
    and (
      c.status = 'accepted'
      or public.are_connected(c.user1_id, c.user2_id)
      -- richiesta mandata da me: la vedo
      or c.requested_by = auth.uid()
      -- richiesta ricevuta: la vedo quando c'è il messaggio
      or (c.requested_by is not null
          and exists (
            select 1 from public.messages m
            where m.conversation_id = c.id
              and m.sender_id = c.requested_by
              and m.created_at >= coalesce(c.requested_at, '-infinity'::timestamptz)
          ))
    )
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by lm.created_at desc nulls last;
$$;

grant execute on function public.get_conversations() to authenticated;

-- ─── 3. Stato della relazione: anche "mi ha bloccato" ────────────────────────
-- La tabella dei blocchi la legge solo chi blocca: per sapere se qualcuno ti
-- ha bloccato serve questa funzione (risponde solo per te, mai per altri).

create or replace function public.get_connection_status(target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (
      select 1 from public.blocked_users
      where blocker_id = auth.uid() and blocked_id = target_user_id
    ) then 'blocked'
    when exists (
      select 1 from public.blocked_users
      where blocker_id = target_user_id and blocked_id = auth.uid()
    ) then 'blocked_by_them'
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

-- ─── 4. Persone taggate in un drop ───────────────────────────────────────────

create or replace function public.get_drop_tags(p_drop_id uuid)
returns table (
  id                uuid,
  username          text,
  display_name      text,
  avatar_url        text,
  memories_count    integer,
  connections_count integer,
  created_at        timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url,
         p.memories_count, p.connections_count, p.created_at
  from public.drop_tags t
  join public.profiles p on p.id = t.tagged_user_id
  join public.memories m on m.id = t.drop_id
  where t.drop_id = p_drop_id
    and (t.tagged_user_id = auth.uid() or not public.is_blocked_pair(t.tagged_user_id))
    and (
      m.user_id = auth.uid()
      or (
        not public.is_blocked_pair(m.user_id)
        and m.visibility <> 'private'
        and (
          t.tagged_user_id = auth.uid()
          or (m.visibility = 'public' and not public.event_has_ended(m.event_id))
          or exists (
            select 1 from public.connections c
            where c.status = 'accepted'
              and (
                (c.requester_id = auth.uid() and c.target_id = m.user_id)
                or (c.target_id = auth.uid() and c.requester_id = m.user_id)
              )
          )
        )
      )
    )
  order by t.created_at asc;
$$;

-- ─── 5. Segnalazioni da leggere nel pannello di Supabase ─────────────────────
-- Table Editor → reports_review: una riga per segnalazione, la più recente in
-- alto, con cosa è stato segnalato. È "security_invoker": dall'app ognuno
-- vede solo le proprie segnalazioni (come nella tabella reports), dal
-- pannello di Supabase le vedi tutte.

create or replace view public.reports_review
with (security_invoker = true) as
select
  r.created_at                                   as segnalata_il,
  case
    when r.memory_id is not null        then 'drop'
    when r.comment_id is not null       then 'commento'
    else 'utente'
  end                                            as tipo,
  rp.username                                    as da,
  coalesce(mp.username, cp.username, up.username) as segnalato,
  coalesce(m.description, c.content)             as contenuto,
  m.image_url                                    as foto,
  r.memory_id,
  r.comment_id,
  r.reported_user_id,
  r.id                                           as report_id
from public.reports r
join public.profiles rp on rp.id = r.reporter_id
left join public.memories m  on m.id = r.memory_id
left join public.profiles mp on mp.id = m.user_id
left join public.comments c  on c.id = r.comment_id
left join public.profiles cp on cp.id = c.user_id
left join public.profiles up on up.id = r.reported_user_id
order by r.created_at desc;

-- ─── 6. Accettare/eliminare: solo richieste vere, ricevute da altri ──────────
-- (una chat chiusa da un blocco non ha mittente e non si "accetta")

create or replace function public.accept_message_request(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.conversations c
  set status = 'accepted'
  where c.id = p_conversation_id
    and c.status = 'pending'
    and c.requested_by is not null
    and c.requested_by <> auth.uid()
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    and not public.is_blocked_pair(c.requested_by);
$$;

create or replace function public.decline_message_request(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.conversations c
  where c.id = p_conversation_id
    and c.status = 'pending'
    and c.requested_by is not null
    and c.requested_by <> auth.uid()
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid());
$$;
