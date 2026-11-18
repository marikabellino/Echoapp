-- ============================================================
-- mingle. — Tutto visibile solo agli utenti registrati
-- Esegui nel SQL Editor di Supabase dopo 033
-- ============================================================
--
-- La chiave pubblica dell'app (anon key) è dentro l'app: chiunque può
-- estrarla e interrogare il database senza fare login. Fino a ora, così,
-- poteva leggere drop pubblici (con le coordinate), profili, commenti,
-- like ed eventi, e aprire le foto dei drop pubblici.
--
-- Da qui in poi chi non ha fatto login ("anon") non legge NIENTE:
-- né tabelle, né funzioni, né foto dei drop. La registrazione e il login
-- non ne risentono: passano da Supabase Auth, non da queste tabelle.

-- ─── Tabelle e viste ─────────────────────────────────────────────────────────
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- ─── Funzioni (RPC) ──────────────────────────────────────────────────────────
-- Di default Postgres concede EXECUTE a tutti (PUBLIC): lo togliamo e lo
-- ridiamo solo agli utenti registrati. Le funzioni usate dai trigger
-- continuano a funzionare: i trigger non passano da questi permessi.
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema public from public;
grant execute on all functions in schema public to authenticated, service_role;

-- ─── Anche per tutto ciò che verrà creato in futuro ─────────────────────────
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public grant execute on functions to authenticated, service_role;

-- ─── Foto dei drop: solo utenti registrati ──────────────────────────────────
alter policy "Storage memories: read if drop visible"
  on storage.objects to authenticated;
