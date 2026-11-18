-- ============================================================
-- mingle. — Visibilità predefinita dei drop: "Cerchia"
-- Esegui nel SQL Editor di Supabase dopo 031
-- ============================================================
-- Scelta prudente per la privacy: se un drop arriva senza visibilità
-- esplicita, nasce visibile solo alla cerchia, non a tutti.
-- I drop agganciati a un evento in corso restano comunque pubblici
-- (lo impone il trigger di 031).

alter table public.memories alter column visibility set default 'circle';
