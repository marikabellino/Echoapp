-- ============================================================
-- Echo App — Messaggistica real-time
-- Esegui nel SQL Editor di Supabase
-- ============================================================

-- ─── Conversations ───────────────────────────────────────────────────────────
-- user1_id < user2_id garantisce unicità senza duplicati speculari

create table if not exists public.conversations (
  id          uuid primary key default gen_random_uuid(),
  user1_id    uuid references public.profiles(id) on delete cascade not null,
  user2_id    uuid references public.profiles(id) on delete cascade not null,
  created_at  timestamptz not null default now(),
  constraint conversations_ordered check (user1_id < user2_id),
  unique (user1_id, user2_id)
);

-- ─── Messages ────────────────────────────────────────────────────────────────

create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations(id) on delete cascade not null,
  sender_id       uuid references public.profiles(id) on delete cascade not null,
  content         text not null,
  created_at      timestamptz not null default now(),
  read_at         timestamptz
);

create index if not exists messages_conv_created_idx
  on public.messages (conversation_id, created_at desc);

create index if not exists messages_unread_idx
  on public.messages (conversation_id, sender_id, read_at)
  where read_at is null;

-- ─── Row Level Security ───────────────────────────────────────────────────────

alter table public.conversations enable row level security;
alter table public.messages      enable row level security;

-- Conversations: solo i partecipanti possono vedere/creare
create policy "Conversations: participants select"
  on public.conversations for select
  using (auth.uid() = user1_id or auth.uid() = user2_id);

create policy "Conversations: participants insert"
  on public.conversations for insert
  with check (auth.uid() = user1_id or auth.uid() = user2_id);

-- Messages: partecipanti della conversazione
create policy "Messages: participants select"
  on public.messages for select
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    )
  );

create policy "Messages: sender insert"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    )
  );

create policy "Messages: sender update read_at"
  on public.messages for update
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    )
  );

-- ─── RPC: get_or_create_conversation ─────────────────────────────────────────
-- Restituisce l'ID della conversazione tra l'utente corrente e other_user_id,
-- creandola se non esiste. Gli ID vengono ordinati per rispettare il check.

create or replace function public.get_or_create_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
as $$
declare
  conv_id uuid;
  u1      uuid;
  u2      uuid;
begin
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

  if conv_id is null then
    insert into public.conversations (user1_id, user2_id)
    values (u1, u2)
    returning id into conv_id;
  end if;

  return conv_id;
end;
$$;

-- ─── RPC: get_conversations ───────────────────────────────────────────────────
-- Lista conversazioni dell'utente corrente con ultimo messaggio e badge unread.

create or replace function public.get_conversations()
returns table (
  conversation_id    uuid,
  other_user_id      uuid,
  other_username     text,
  other_display_name text,
  other_avatar_url   text,
  last_message       text,
  last_message_at    timestamptz,
  unread_count       bigint
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
    select content, created_at
    from public.messages
    where conversation_id = c.id
    order by created_at desc
    limit 1
  ) lm on true
  where c.user1_id = auth.uid() or c.user2_id = auth.uid()
  order by lm.created_at desc nulls last;
$$;

-- ─── RPC: mark_messages_read ──────────────────────────────────────────────────

create or replace function public.mark_messages_read(p_conversation_id uuid)
returns void
language sql
volatile
security definer
as $$
  update public.messages
  set read_at = now()
  where conversation_id = p_conversation_id
    and sender_id != auth.uid()
    and read_at is null;
$$;

-- ─── Realtime ─────────────────────────────────────────────────────────────────
-- Abilita Realtime sulla tabella messages per i channel subscriptions.

alter publication supabase_realtime add table public.messages;
