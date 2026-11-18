-- ============================================================
-- mingle. — Foto dei drop private, con link temporanei firmati
-- Esegui nel SQL Editor di Supabase dopo 032.
-- ⚠️ Prima pubblica la versione dell'app che usa i link firmati
--    (DropImageSigner): le versioni vecchie usano i link pubblici e,
--    dopo questa migrazione, non vedrebbero più le foto.
-- ============================================================
--
-- Prima: il bucket "memories" era pubblico. Chiunque avesse il link esatto
-- di una foto poteva aprirla per sempre, anche se il drop era privato o di
-- cerchia, anche dopo essere uscito dalla cerchia o essere stato bloccato.
--
-- Ora: il bucket è privato. Una foto si apre solo con un link firmato e a
-- tempo, e Supabase firma il link solo per chi può vedere il drop che la
-- contiene. La regola usa direttamente "Memories: read" (cerchia, blocchi,
-- eventi finiti, drop privati), quindi non può andare fuori sincrono.

-- ─── Percorso del file, ricavato da image_url ────────────────────────────────
-- image_url resta com'è (".../object/public/memories/<user>/<token>.jpg"):
-- ne estraiamo il percorso in una colonna indicizzata, usata dalla regola.

alter table public.memories
  add column if not exists image_path text
  generated always as (
    substring(image_url from '/object/(?:public|sign|authenticated)/memories/([^?]+)')
  ) stored;

create index if not exists memories_image_path_idx
  on public.memories (image_path);

-- ─── Regola di lettura dei file ──────────────────────────────────────────────
-- Il proprietario legge sempre i suoi file (serve anche per caricarli e per
-- cancellare l'account). Gli altri possono leggere un file solo se esiste un
-- drop che lo usa e che loro possono vedere: la sottoquery su memories passa
-- dalla regola "Memories: read" dell'utente che chiede.

drop policy if exists "Storage memories: owner read" on storage.objects;
drop policy if exists "Storage memories: read if drop visible" on storage.objects;

create policy "Storage memories: read if drop visible"
  on storage.objects for select
  using (
    bucket_id = 'memories'
    and (
      auth.uid()::text = (storage.foldername(name))[1]
      or exists (
        select 1 from public.memories m
        where m.image_path = storage.objects.name
      )
    )
  );

-- ─── Bucket privato ──────────────────────────────────────────────────────────
-- Da qui i link ".../object/public/memories/..." smettono di funzionare.

update storage.buckets set public = false where id = 'memories';
