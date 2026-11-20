-- 039 · Tempo reale che regge tanta gente
--
-- Prima: ogni telefono collegato riceveva TUTTI i like e TUTTI i messaggi
-- dell'app, e per ognuno il database controllava se quel telefono poteva
-- vederlo. Con 2.000 persone online, un like = 2.000 controlli.
-- Ora like e messaggi hanno una colonna con il destinatario, e l'app si
-- iscrive solo ai propri: il database scarta subito tutto il resto.
--
-- Va eseguita PRIMA di installare la nuova versione dell'app (che filtra
-- su queste colonne). Si può rieseguire senza problemi.

-- ─── Like: a chi appartiene il drop ──────────────────────────────────────────

alter table public.likes
  add column if not exists drop_owner_id uuid references public.profiles(id) on delete cascade;

create or replace function public.likes_set_drop_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select m.user_id into new.drop_owner_id
  from public.memories m
  where m.id = new.memory_id;
  return new;
end;
$$;

drop trigger if exists likes_set_drop_owner on public.likes;
create trigger likes_set_drop_owner
  before insert on public.likes
  for each row execute function public.likes_set_drop_owner();

update public.likes l
set drop_owner_id = m.user_id
from public.memories m
where m.id = l.memory_id and l.drop_owner_id is null;

create index if not exists likes_drop_owner_idx on public.likes (drop_owner_id);

-- ─── Messaggi: chi li riceve ─────────────────────────────────────────────────

alter table public.messages
  add column if not exists recipient_id uuid references public.profiles(id) on delete cascade;

create or replace function public.messages_set_recipient()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select case when c.user1_id = new.sender_id then c.user2_id else c.user1_id end
    into new.recipient_id
  from public.conversations c
  where c.id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_set_recipient on public.messages;
create trigger messages_set_recipient
  before insert on public.messages
  for each row execute function public.messages_set_recipient();

update public.messages m
set recipient_id = case when c.user1_id = m.sender_id then c.user2_id else c.user1_id end
from public.conversations c
where c.id = m.conversation_id and m.recipient_id is null;

create index if not exists messages_recipient_idx on public.messages (recipient_id);

-- ─── Tabelle in tempo reale ──────────────────────────────────────────────────
-- likes e connections servono alle notifiche in app: le aggiungiamo alla
-- pubblicazione solo se non ci sono già.

do $$
declare t text;
begin
  foreach t in array array['likes', 'connections', 'messages', 'memories', 'drop_tags', 'comment_tags'] loop
    if to_regclass('public.' || t) is not null and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- ─── Eventi finiti: ogni 5 minuti invece che a ogni apertura del feed ───────
-- Prima l'app chiamava downgrade_expired_event_drops() a ogni caricamento
-- del feed e dei profili (una scrittura nel database per ogni apertura).
-- Ora lo fa il database da solo ogni 5 minuti. Anche nei minuti di attesa
-- nessuno vede ciò che non deve: la regola di lettura dei drop tratta già i
-- drop pubblici di un evento finito come "solo cerchia".

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'mingle-downgrade-event-drops',
  '*/5 * * * *',
  $$select public.downgrade_expired_event_drops()$$
);
