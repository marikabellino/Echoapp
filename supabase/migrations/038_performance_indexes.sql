-- 038 · Prestazioni per il lancio
--
-- Nessun cambiamento di comportamento: solo indici (le "scorciatoie" che
-- permettono al database di trovare le righe senza scorrere tutta la
-- tabella) e la regola di lettura dei drop riscritta in forma più veloce.
-- Con pochi utenti non si nota; con decine di migliaia di drop, like e
-- messaggi è la differenza tra una risposta istantanea e una lenta.
--
-- Si può rieseguire senza problemi (if not exists / drop if exists).

-- ─── Drop (memories) ─────────────────────────────────────────────────────────

-- Mappa: drop in un riquadro di lat/lng, esclusi quelli "a casa".
create index if not exists memories_geo_idx
  on public.memories (latitude, longitude)
  where at_home = false;

-- Feed Esplora: i più recenti, esclusi i privati.
create index if not exists memories_feed_idx
  on public.memories (created_at desc)
  where visibility <> 'private';

-- Profilo: i drop di una persona, dal più recente.
create index if not exists memories_user_created_idx
  on public.memories (user_id, created_at desc);

-- Pagina evento: i drop dell'evento, dal più recente.
create index if not exists memories_event_created_idx
  on public.memories (event_id, created_at desc)
  where event_id is not null;

-- downgrade_expired_event_drops() gira a ogni apertura del feed: cerca solo
-- i drop pubblici agganciati a un evento.
create index if not exists memories_public_event_idx
  on public.memories (event_id)
  where visibility = 'public' and event_id is not null;

-- ─── Like e commenti ─────────────────────────────────────────────────────────

-- "Chi ha messo like" e il conteggio per drop (l'unique esistente parte da
-- user_id, quindi non serve per cercare per drop).
create index if not exists likes_memory_created_idx
  on public.likes (memory_id, created_at desc);

-- Commenti di un drop in ordine.
create index if not exists comments_memory_created_idx
  on public.comments (memory_id, created_at);

create index if not exists comments_user_idx
  on public.comments (user_id);

-- ─── Chat ────────────────────────────────────────────────────────────────────

-- L'unique (user1_id, user2_id) copre le ricerche per user1: serve anche
-- quello per user2, altrimenti metà delle chat di ognuno si trova lentamente.
create index if not exists conversations_user2_idx
  on public.conversations (user2_id);

create index if not exists messages_sender_idx
  on public.messages (sender_id);

-- ─── Segnalazioni ────────────────────────────────────────────────────────────

create index if not exists reports_memory_idx
  on public.reports (memory_id) where memory_id is not null;
create index if not exists reports_reported_user_idx
  on public.reports (reported_user_id) where reported_user_id is not null;
create index if not exists reports_comment_idx
  on public.reports (comment_id) where comment_id is not null;
create index if not exists reports_created_idx
  on public.reports (created_at desc);

-- ─── Cerchia ─────────────────────────────────────────────────────────────────

-- La regola di lettura dei drop "cerchia" controlla le amicizie accettate
-- in entrambe le direzioni.
create index if not exists connections_accepted_pair_idx
  on public.connections (target_id, requester_id)
  where status = 'accepted';

-- ─── Ricerca utenti ──────────────────────────────────────────────────────────

-- search_users usa ilike '%testo%': senza questo indice scorre tutti i
-- profili a ogni lettera digitata.
create extension if not exists pg_trgm with schema extensions;

create index if not exists profiles_username_trgm_idx
  on public.profiles using gin (username extensions.gin_trgm_ops);
create index if not exists profiles_display_name_trgm_idx
  on public.profiles using gin (display_name extensions.gin_trgm_ops);

-- ─── Regola di lettura dei drop, versione veloce ─────────────────────────────

-- Identica a quella di 031, ma con (select auth.uid()) al posto di
-- auth.uid(): così Postgres calcola l'utente una volta sola per query invece
-- che una volta per ogni drop (consiglio ufficiale di Supabase per l'RLS).
drop policy if exists "Memories: read" on public.memories;

create policy "Memories: read"
  on public.memories for select
  using (
    (select auth.uid()) = user_id
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
                (c.requester_id = (select auth.uid()) and c.target_id = memories.user_id)
                or (c.target_id = (select auth.uid()) and c.requester_id = memories.user_id)
              )
          )
        )
        -- Taggati: mai sui drop privati
        or (
          visibility <> 'private'
          and exists (
            select 1 from public.drop_tags t
            where t.drop_id = memories.id and t.tagged_user_id = (select auth.uid())
          )
        )
      )
    )
  );

-- Statistiche aggiornate, così il database sceglie subito gli indici nuovi.
analyze public.memories;
analyze public.likes;
analyze public.comments;
analyze public.conversations;
analyze public.messages;
analyze public.connections;
analyze public.profiles;
