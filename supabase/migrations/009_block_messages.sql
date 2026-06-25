-- ============================================================
-- Echo App — Blocco messaggi per utenti bloccati
-- Esegui nel SQL Editor di Supabase dopo 008
-- ============================================================

-- ─── Fix: RLS SELECT su messages — nega lettura se c'è un blocco ─────────────
-- La policy originale controllava solo la partecipazione, non i blocchi.

drop policy if exists "Messages: participants select" on public.messages;

create policy "Messages: participants select"
  on public.messages for select
  using (
    -- deve essere partecipante della conversazione
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    )
    -- nega se esiste un blocco in qualsiasi direzione
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

-- ─── Fix: RLS INSERT su messages — nega invio se c'è un blocco ───────────────
-- La policy originale non controllava blocked_users, quindi un utente bloccato
-- poteva comunque inserire messaggi nel DB.

drop policy if exists "Messages: sender insert" on public.messages;

create policy "Messages: sender insert"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    -- mittente deve essere partecipante della conversazione
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    )
    -- nega se esiste un blocco in qualsiasi direzione tra i due utenti
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

-- ─── Fix: get_conversations — esclude conversazioni con bloccati ──────────────

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
  where (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    -- esclude conversazioni dove c'è un blocco in qualsiasi direzione
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = auth.uid())
    )
  order by lm.created_at desc nulls last;
$$;

-- ─── Fix: get_or_create_conversation — nega creazione con bloccati ────────────

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
