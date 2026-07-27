-- ============================================================
-- Echo App — Tag persone nei commenti + notifica
-- Esegui nel SQL Editor di Supabase dopo 024
-- ============================================================

-- Stessa impostazione di drop_tags (015): tabella con RLS ristretta (solo
-- taggato/taggante possono leggere direttamente, per l'affidabilità del
-- realtime — niente join nella policy SELECT), inserimento solo via RPC
-- security definer che valida proprietà del commento + cerchia + blocchi.

create table if not exists public.comment_tags (
  id                uuid primary key default gen_random_uuid(),
  comment_id        uuid references public.comments(id) on delete cascade not null,
  tagged_user_id    uuid references public.profiles(id) on delete cascade not null,
  tagged_by         uuid references public.profiles(id) on delete cascade not null,
  created_at        timestamptz not null default now(),
  unique (comment_id, tagged_user_id)
);

create index if not exists comment_tags_tagged_user_idx on public.comment_tags (tagged_user_id);
create index if not exists comment_tags_comment_idx     on public.comment_tags (comment_id);

alter table public.comment_tags enable row level security;

create policy "CommentTags: select own"
  on public.comment_tags for select
  using (auth.uid() = tagged_user_id or auth.uid() = tagged_by);

create policy "CommentTags: tagger deletes"
  on public.comment_tags for delete
  using (auth.uid() = tagged_by);

-- Nessuna policy INSERT diretta: passa solo dalla RPC qui sotto.

-- ─── RPC: tag_users_on_comment ─────────────────────────────────────────────────
-- Tagga persone in un commento di tua proprietà. Stesso filtro silenzioso di
-- tag_users_on_drop: solo cerchia accettata, esclusi i bloccati.

create function public.tag_users_on_comment(p_comment_id uuid, p_user_ids uuid[])
returns table (tagged_user_id uuid)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if not exists (
    select 1 from public.comments c
    where c.id = p_comment_id and c.user_id = auth.uid()
  ) then
    raise exception 'not_owner';
  end if;

  return query
  insert into public.comment_tags (comment_id, tagged_user_id, tagged_by)
  select p_comment_id, u, auth.uid()
  from unnest(p_user_ids) as u
  where u != auth.uid()
    and exists (
      select 1 from public.connections c
      where c.status = 'accepted'
        and (
          (c.requester_id = auth.uid() and c.target_id = u)
          or (c.target_id = auth.uid() and c.requester_id = u)
        )
    )
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = u)
         or (b.blocker_id = u and b.blocked_id = auth.uid())
    )
  on conflict (comment_id, tagged_user_id) do nothing
  returning comment_tags.tagged_user_id;
end;
$$;

grant execute on function public.tag_users_on_comment(uuid, uuid[]) to authenticated;

-- ─── Realtime + push per la notifica "sei stato taggato in un commento" ──────
-- Dopo aver eseguito questa migration, nel dashboard Supabase:
-- 1. Database → Replication: verificare che comment_tags sia inclusa (fatto
--    anche da questa migration via alter publication).
-- 2. Database → Webhooks: registrare un webhook INSERT su comment_tags verso
--    l'edge function send-push (stesso pattern di likes/connections/messages/
--    drop_tags/memories).

alter publication supabase_realtime add table public.comment_tags;
