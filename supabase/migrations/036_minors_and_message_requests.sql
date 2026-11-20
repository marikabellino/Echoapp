-- mingle. — Utenti tra 16 e 17 anni e richieste di messaggio
--
-- L'età minima scende a 16 anni. Per chi non è ancora maggiorenne:
--  1. può scrivere in chat solo alle persone della propria cerchia (e solo
--     loro possono scrivergli): niente richieste di messaggio da sconosciuti.
--     Per tutti gli altri, fuori dalla cerchia si manda una "richiesta di
--     messaggio" che va accettata (sezione 2);
--  2. non può pubblicare drop visibili a tutti: diventano "cerchia", anche
--     quelli lasciati a un evento;
--  3. non può lasciare drop agli eventi segnati come "solo maggiorenni"
--     (per esempio serate con alcolici); l'app mostra un avviso sugli eventi.
--
-- La data di nascita sta in una tabella a parte, leggibile solo dal diretto
-- interessato: i profili sono visibili agli altri utenti, la data di nascita
-- no. Chi si è registrato quando l'app era 18+ non ha una data: conta come
-- maggiorenne (lo aveva dichiarato all'iscrizione).

-- ─── 1. Data di nascita ──────────────────────────────────────────────────────

create table if not exists public.profile_birthdates (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  birth_date date not null,
  created_at timestamptz not null default now()
);

alter table public.profile_birthdates enable row level security;

drop policy if exists "Birthdates: owner read" on public.profile_birthdates;
create policy "Birthdates: owner read"
  on public.profile_birthdates for select
  using (user_id = auth.uid());
-- Nessuna policy di insert/update/delete: la data la scrive solo il trigger
-- di registrazione e non si può cambiare dall'app.

create or replace function public.is_minor(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select b.birth_date > (current_date - interval '18 years')::date
     from public.profile_birthdates b
     where b.user_id = p_user),
    false
  );
$$;

grant execute on function public.is_minor(uuid) to authenticated;

-- Il profilo viene creato alla registrazione con i dati passati dall'app
-- (username, nome, data di nascita). Sotto i 16 anni la registrazione fallisce.
create or replace function public.on_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_birth date;
begin
  begin
    v_birth := nullif(new.raw_user_meta_data->>'birth_date', '')::date;
  exception when others then
    v_birth := null;
  end;

  if v_birth is not null and v_birth > (current_date - interval '16 years')::date then
    raise exception 'too_young'
      using hint = 'Per usare mingle. bisogna avere almeno 16 anni.';
  end if;

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'username',
      split_part(new.email, '@', 1)
    ),
    coalesce(
      new.raw_user_meta_data->>'display_name',
      new.raw_user_meta_data->>'username',
      split_part(new.email, '@', 1)
    )
  );

  if v_birth is not null then
    insert into public.profile_birthdates (user_id, birth_date)
    values (new.id, v_birth);
  end if;

  return new;
end;
$$;

-- ─── 2. Chat: libera solo nella cerchia, altrimenti "richiesta di messaggio" ─
-- Per tutti: due persone della stessa cerchia si scrivono liberamente. Chi
-- non è nella cerchia può mandare una sola "richiesta di messaggio" (il primo
-- messaggio); chi la riceve può accettarla (da lì in poi si scrivono), oppure
-- eliminarla o segnalarla. Con i minorenni niente richieste: solo cerchia.
-- Le conversazioni già esistenti restano aperte.

alter table public.conversations
  add column if not exists status text not null default 'accepted'
    check (status in ('pending', 'accepted')),
  add column if not exists requested_by uuid references public.profiles(id) on delete cascade;

-- Le conversazioni si creano solo da get_or_create_conversation, che decide
-- se è una chat o una richiesta: niente inserimenti diretti dall'app.
drop policy if exists "Conversations: participants insert" on public.conversations;

create or replace function public.are_connected(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.connections c
    where c.status = 'accepted'
      and ((c.requester_id = a and c.target_id = b)
        or (c.requester_id = b and c.target_id = a))
  );
$$;

-- Chi sta scrivendo (auth.uid()) può mandare un messaggio in questa
-- conversazione?
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
      and (
        -- stessa cerchia: sempre
        public.are_connected(c.user1_id, c.user2_id)
        or (
          not public.is_minor(c.user1_id) and not public.is_minor(c.user2_id)
          and (
            -- richiesta accettata
            c.status = 'accepted'
            -- richiesta in attesa: solo chi la manda, un solo messaggio
            or (c.status = 'pending'
                and c.requested_by = auth.uid()
                and not exists (
                  select 1 from public.messages m
                  where m.conversation_id = c.id
                ))
          )
        )
      )
  );
$$;

grant execute on function public.can_send_message(uuid) to authenticated;

create or replace function public.get_or_create_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conv_id   uuid;
  u1        uuid;
  u2        uuid;
  connected boolean;
begin
  -- Impedisce di aprire una conversazione con se stessi
  if other_user_id = auth.uid() then
    raise exception 'self';
  end if;

  -- Impedisce di avviare una chat con un utente bloccato o che ti ha bloccato
  if exists (
    select 1 from public.blocked_users b
    where (b.blocker_id = auth.uid() and b.blocked_id = other_user_id)
       or (b.blocker_id = other_user_id and b.blocked_id = auth.uid())
  ) then
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

  select id into conv_id
  from public.conversations
  where user1_id = u1 and user2_id = u2;

  if conv_id is not null then
    -- Una richiesta tra persone che nel frattempo sono entrate nella stessa
    -- cerchia diventa una chat normale.
    if connected then
      update public.conversations
      set status = 'accepted'
      where id = conv_id and status = 'pending';
    end if;
    return conv_id;
  end if;

  if not connected
     and (public.is_minor(auth.uid()) or public.is_minor(other_user_id)) then
    raise exception 'minor_circle_only';
  end if;

  insert into public.conversations (user1_id, user2_id, status, requested_by)
  values (
    u1, u2,
    case when connected then 'accepted' else 'pending' end,
    case when connected then null else auth.uid() end
  )
  returning id into conv_id;

  return conv_id;
end;
$$;

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
    and c.requested_by is distinct from auth.uid()
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid());
$$;

-- Eliminare una richiesta la cancella del tutto, messaggio compreso: chi
-- l'ha mandata potrà riprovare (a meno di un blocco).
create or replace function public.decline_message_request(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.conversations c
  where c.id = p_conversation_id
    and c.status = 'pending'
    and c.requested_by is distinct from auth.uid()
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid());
$$;

grant execute on function public.accept_message_request(uuid) to authenticated;
grant execute on function public.decline_message_request(uuid) to authenticated;

drop policy if exists "Messages: sender insert" on public.messages;

create policy "Messages: sender insert"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    and public.can_send_message(conversation_id)
    and not exists (
      select 1
      from public.conversations c2,
           public.blocked_users b
      where c2.id = conversation_id
        and (
          (b.blocker_id = auth.uid() and b.blocked_id = case when c2.user1_id = auth.uid() then c2.user2_id else c2.user1_id end)
          or
          (b.blocked_id = auth.uid() and b.blocker_id = case when c2.user1_id = auth.uid() then c2.user2_id else c2.user1_id end)
        )
    )
  );

-- Elenco chat: come prima, più lo stato (chat o richiesta) e chi l'ha
-- mandata. Una richiesta ancora vuota (nessun messaggio) non compare a chi la
-- riceve.
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
    and not (c.status = 'pending'
             and c.requested_by is distinct from auth.uid()
             and lm.created_at is null)
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by lm.created_at desc nulls last;
$$;

grant execute on function public.get_conversations() to authenticated;

-- ─── 3. Eventi "solo maggiorenni" ────────────────────────────────────────────

alter table public.events
  add column if not exists adults_only boolean not null default false;

-- ─── 4. Drop dei minorenni: mai pubblici, mai su eventi 18+ ──────────────────
-- Il nome "memories_z_..." fa girare questo trigger dopo quello degli eventi
-- (che imposta "pubblico" sui drop di un evento): i trigger BEFORE girano in
-- ordine alfabetico.

create or replace function public.protect_minor_drop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_minor(new.user_id) then
    return new;
  end if;

  if new.event_id is not null
     and (tg_op = 'INSERT' or new.event_id is distinct from old.event_id)
     and exists (select 1 from public.events e where e.id = new.event_id and e.adults_only) then
    raise exception 'event_adults_only'
      using hint = 'Questo evento è riservato ai maggiorenni.';
  end if;

  if new.visibility = 'public' then
    new.visibility := 'circle';
  end if;
  return new;
end;
$$;

drop trigger if exists memories_z_protect_minor on public.memories;
create trigger memories_z_protect_minor
  before insert or update on public.memories
  for each row execute function public.protect_minor_drop();
