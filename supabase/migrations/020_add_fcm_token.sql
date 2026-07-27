-- Colonna per il token FCM del dispositivo, usata da supabase/functions/send-push
-- per inviare le push quando l'app è in background o killed.
-- Senza questa colonna, l'update in FcmService._saveToken() falliva silenziosamente
-- e send-push non trovava mai un token a cui inviare.

alter table profiles add column if not exists fcm_token text;
