-- ============================================================
-- Echo App — Anteprima GIF nella lista conversazioni
-- Esegui nel SQL Editor di Supabase dopo 022
-- ============================================================

-- get_conversations selezionava solo messages.content per l'anteprima
-- dell'ultimo messaggio. Un messaggio-GIF ha content = '' (vedi
-- sendGif in messaging_provider.dart), quindi la lista mostrava una riga
-- vuota invece di segnalare che l'ultimo messaggio è una GIF. Aggiungiamo
-- gif_url all'output così il client sa quando mostrare "GIF" al posto del
-- testo (017_message_gifs.sql aveva introdotto la colonna ma non l'aveva
-- propagata qui).

-- CREATE OR REPLACE non permette di cambiare l'elenco delle colonne di
-- ritorno di una funzione esistente: va droppata e ricreata.
drop function if exists public.get_conversations();

create function public.get_conversations()
returns table (
  conversation_id    uuid,
  other_user_id       uuid,
  other_username      text,
  other_display_name  text,
  other_avatar_url    text,
  last_message        text,
  last_message_gif_url text,
  last_message_at     timestamptz,
  unread_count        bigint
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
    select content, gif_url, created_at
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
