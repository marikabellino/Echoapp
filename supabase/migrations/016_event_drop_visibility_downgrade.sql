-- ============================================================
-- Echo App — Downgrade visibilità drop legati a un evento concluso
-- Esegui nel SQL Editor di Supabase dopo 015
-- ============================================================

-- ─── Perché ────────────────────────────────────────────────────────────────
-- Un drop agganciato a un evento viene creato con visibility='public' (vedi
-- create_page.dart, la pillola visibilità è bloccata su Pubblico quando è
-- selezionato un evento) così chiunque lo trova nella categoria dell'evento
-- finché questo è attivo. Al termine dell'evento non deve più comparire nel
-- feed pubblico: torna visibile solo all'autore e alla sua cerchia
-- (visibility='circle'), esattamente come un drop cerchia normale — l'autore
-- lo ritrova comunque sul proprio profilo.
--
-- Niente pg_cron: la funzione viene chiamata "a costo zero" (RPC leggera,
-- filtrata sull'utente corrente) dal client a ogni fetch dei propri drop o
-- del feed Discover (vedi drop_repository.dart), quindi il downgrade avviene
-- entro la normale attività dell'app senza bisogno di job schedulati né di
-- setup aggiuntivo nel dashboard.

create or replace function public.downgrade_expired_event_drops()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.memories m
  set visibility = 'circle'
  where m.user_id = auth.uid()
    and m.visibility = 'public'
    and m.event_id is not null
    and exists (
      select 1 from public.events e
      where e.id = m.event_id and e.ends_at < now()
    );
$$;

grant execute on function public.downgrade_expired_event_drops() to authenticated;
