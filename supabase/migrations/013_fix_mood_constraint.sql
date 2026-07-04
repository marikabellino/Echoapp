-- ============================================================
-- Echo App — Aggiorna il vincolo su memories.mood
-- Il check originale (001_initial_schema) accettava solo
-- ('echo','love','secret','dream','lost'): mancano 'drop' (il mood
-- di default!) e 'food', introdotti quando l'app è passata dai vecchi
-- nomi "Echo" ai nuovi "Drop". Qualsiasi insert col mood di default
-- veniva rifiutato dal database con una violazione di constraint.
-- Esegui nel SQL Editor del tuo progetto Supabase.
-- ============================================================

do $$
declare
  con record;
begin
  for con in
    select conname from pg_constraint
    where conrelid = 'public.memories'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%mood%'
  loop
    execute format('alter table public.memories drop constraint %I', con.conname);
  end loop;
end $$;

alter table public.memories
  add constraint memories_mood_check
  check (mood in ('echo', 'drop', 'love', 'secret', 'dream', 'lost', 'food'));
