-- ============================================================
-- Echo App — Notifiche per nuovi drop della cerchia
-- Esegui nel SQL Editor di Supabase dopo 023
-- ============================================================

-- Serve alla subscription in-app in notification_service.dart
-- (_subscribeCircleDrops): senza questo, Postgres Changes non emette eventi
-- per gli insert su memories e la notifica in-app non arriva mai (la push
-- via Database Webhook non dipende da questa publication, è un meccanismo
-- separato — va comunque registrato il webhook, vedi il commento in testa a
-- supabase/functions/send-push/index.ts).

alter publication supabase_realtime add table public.memories;
