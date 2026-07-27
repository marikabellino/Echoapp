-- Limiti sui bucket Storage (nessuno era impostato: upload illimitati lato server)
update storage.buckets
  set file_size_limit = 5242880, -- 5 MB, con margine sopra la compressione client (~1200px/q80)
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
  where id in ('memories', 'avatars');

-- Policy di cancellazione mancante su "memories": senza questa, deleteDrop()
-- poteva rimuovere solo la riga in tabella ma non il file, lasciando immagini
-- orfane su Storage per sempre.
create policy "Storage memories: owner delete"
  on storage.objects for delete
  using (bucket_id = 'memories' and auth.uid()::text = (storage.foldername(name))[1]);

-- Idem per "avatars": mancava la delete policy (c'era solo update).
create policy "Storage avatars: owner delete"
  on storage.objects for delete
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
