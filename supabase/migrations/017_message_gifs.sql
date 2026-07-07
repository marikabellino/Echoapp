-- ============================================================
-- Echo App — Invio GIF nei messaggi
-- Esegui nel SQL Editor di Supabase dopo 016
-- ============================================================

-- Un messaggio GIF ha content='' e gif_url valorizzato — nessuna modifica
-- alle policy RLS esistenti su "messages": non fanno distinzioni sul
-- contenuto delle colonne, solo su partecipazione/blocchi.

alter table public.messages
  add column if not exists gif_url text;
