-- ============================================================
-- Echo App — Contatore commenti denormalizzato su memories
-- Esegui nel SQL Editor di Supabase
-- ============================================================

-- ─── Colonna comments_count ───────────────────────────────────────────────────

alter table public.memories
  add column if not exists comments_count integer not null default 0;

-- Backfill per ricordi già esistenti
update public.memories m
set comments_count = (
  select count(*) from public.comments c where c.memory_id = m.id
);

-- ─── Policy delete commenti propri ────────────────────────────────────────────
-- (La tabella comments esiste già da 001, aggiungiamo solo la delete policy)

drop policy if exists "Comments: self delete" on public.comments;
create policy "Comments: self delete"
  on public.comments for delete
  using (auth.uid() = user_id);

  

-- ─── Trigger: increment su insert ────────────────────────────────────────────

create or replace function public.on_comment_inserted()
returns trigger language plpgsql security definer as $$
begin
  update public.memories
  set comments_count = comments_count + 1
  where id = new.memory_id;
  return new;
end;
$$;

drop trigger if exists on_comment_inserted on public.comments;
create trigger on_comment_inserted
  after insert on public.comments
  for each row execute function public.on_comment_inserted();

-- ─── Trigger: decrement su delete ────────────────────────────────────────────

create or replace function public.on_comment_deleted()
returns trigger language plpgsql security definer as $$
begin
  update public.memories
  set comments_count = greatest(0, comments_count - 1)
  where id = old.memory_id;
  return old;
end;
$$;

drop trigger if exists on_comment_deleted on public.comments;
create trigger on_comment_deleted
  after delete on public.comments
  for each row execute function public.on_comment_deleted();
