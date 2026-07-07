-- ============================================================
-- Echo App — Fix affidabilità Realtime su messages
-- Esegui nel SQL Editor di Supabase dopo 013
-- ============================================================

-- ─── Perché ────────────────────────────────────────────────────────────────
-- Postgres Changes ri-verifica la RLS di "messages" per ogni subscriber a ogni
-- insert, incluse le policy delle tabelle referenziate nei join (conversations,
-- blocked_users). La policy attuale fa un doppio join/exists, rendendo il check
-- lento e meno affidabile — le notifiche in-app sui messaggi possono non
-- arrivare anche se l'utente è un legittimo partecipante.
--
-- Spostando il check in una funzione security definer, Postgres Changes valuta
-- una singola funzione invece di ri-eseguire la RLS di due tabelle annidate.
--
-- Bonus: la vecchia policy "not exists" su blocked_users poteva vedere solo i
-- blocchi creati dall'utente corrente (RLS "select own" filtra su
-- blocker_id = auth.uid()), quindi il controllo "mi ha bloccato l'altro utente"
-- non vedeva mai quella riga. La funzione security definer, bypassando la RLS
-- di blocked_users, valuta correttamente il blocco in entrambe le direzioni.

create or replace function public.can_view_conversation_messages(p_conversation_id uuid)
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
  )
  and not exists (
    select 1
    from public.conversations c2
    join public.blocked_users b
      on (
        (b.blocker_id = auth.uid() and b.blocked_id = case when c2.user1_id = auth.uid() then c2.user2_id else c2.user1_id end)
        or
        (b.blocked_id = auth.uid() and b.blocker_id = case when c2.user1_id = auth.uid() then c2.user2_id else c2.user1_id end)
      )
    where c2.id = p_conversation_id
  );
$$;

grant execute on function public.can_view_conversation_messages(uuid) to authenticated;

drop policy if exists "Messages: participants select" on public.messages;

create policy "Messages: participants select"
  on public.messages for select
  using (public.can_view_conversation_messages(conversation_id));
