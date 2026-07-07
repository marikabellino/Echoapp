-- ============================================================
-- Echo App — Tag persone nei drop
-- Esegui nel SQL Editor di Supabase dopo 014
-- ============================================================

-- ─── Tabella drop_tags ────────────────────────────────────────────────────────

create table if not exists public.drop_tags (
  id                uuid primary key default gen_random_uuid(),
  drop_id           uuid references public.memories(id) on delete cascade not null,
  tagged_user_id    uuid references public.profiles(id) on delete cascade not null,
  tagged_by         uuid references public.profiles(id) on delete cascade not null,
  hidden_by_tagged  boolean not null default false,
  created_at        timestamptz not null default now(),
  unique (drop_id, tagged_user_id)
);

create index if not exists drop_tags_tagged_user_idx on public.drop_tags (tagged_user_id);
create index if not exists drop_tags_drop_idx        on public.drop_tags (drop_id);

alter table public.drop_tags enable row level security;

-- SELECT: solo il taggato o chi ha taggato vedono direttamente la riga.
-- Volutamente senza join ad altre tabelle: questa policy viene ri-valutata da
-- Postgres Changes per ogni evento/subscriber (notifica realtime "sei stato
-- taggato") — un check su singola colonna evita il problema di affidabilità
-- già risolto per "messages" in 014_fix_messages_realtime_rls.sql. La lista
-- "chi è taggato in questo drop" per un terzo che guarda il post passa invece
-- dalla RPC get_drop_tags qui sotto, che applica la sua visibilità a parte.
create policy "DropTags: select own"
  on public.drop_tags for select
  using (auth.uid() = tagged_user_id or auth.uid() = tagged_by);

-- UPDATE: il taggato può nascondere/mostrare il tag sul proprio profilo.
create policy "DropTags: tagged toggles hidden"
  on public.drop_tags for update
  using (auth.uid() = tagged_user_id)
  with check (auth.uid() = tagged_user_id);

-- DELETE: chi ha taggato può rimuovere un tag messo per errore.
create policy "DropTags: tagger deletes"
  on public.drop_tags for delete
  using (auth.uid() = tagged_by);

-- Nessuna policy INSERT diretta: l'inserimento passa solo dalla RPC
-- tag_users_on_drop, che valida proprietà del drop, cerchia e blocchi.

-- ─── Estendi RLS memories: il taggato vede il drop anche se privato ──────────

drop policy if exists "Memories: read" on public.memories;

create policy "Memories: read"
  on public.memories for select
  using (
    auth.uid() = user_id
    or visibility = 'public'
    or (
      visibility = 'circle'
      and exists (
        select 1 from public.connections c
        where c.status = 'accepted'
          and (
            (c.requester_id = auth.uid() and c.target_id = memories.user_id)
            or (c.target_id = auth.uid() and c.requester_id = memories.user_id)
          )
      )
    )
    or exists (
      select 1 from public.drop_tags t
      where t.drop_id = memories.id and t.tagged_user_id = auth.uid()
    )
  );

-- ─── RPC: tag_users_on_drop ───────────────────────────────────────────────────
-- Tagga più persone su un drop di tua proprietà. Filtra silenziosamente chi
-- non è nella tua cerchia (connessione accettata) o è bloccato in una delle
-- due direzioni, così il client non deve replicare questi controlli.

create or replace function public.tag_users_on_drop(p_drop_id uuid, p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.memories m
    where m.id = p_drop_id and m.user_id = auth.uid()
  ) then
    raise exception 'not_owner';
  end if;

  insert into public.drop_tags (drop_id, tagged_user_id, tagged_by)
  select p_drop_id, u, auth.uid()
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
  on conflict (drop_id, tagged_user_id) do nothing;
end;
$$;

grant execute on function public.tag_users_on_drop(uuid, uuid[]) to authenticated;

-- ─── RPC: get_drop_tags ───────────────────────────────────────────────────────
-- Persone taggate in un drop, visibile a chiunque possa vedere il drop stesso
-- (stessa logica della RLS "Memories: read" qui sopra, valutata una volta sola
-- per chiamata anziché per-subscriber: qui i join non sono un problema).

create or replace function public.get_drop_tags(p_drop_id uuid)
returns table (
  id                uuid,
  username          text,
  display_name      text,
  avatar_url        text,
  memories_count    integer,
  connections_count integer,
  created_at        timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url,
         p.memories_count, p.connections_count, p.created_at
  from public.drop_tags t
  join public.profiles p on p.id = t.tagged_user_id
  join public.memories m on m.id = t.drop_id
  where t.drop_id = p_drop_id
    and (
      m.user_id = auth.uid()
      or t.tagged_user_id = auth.uid()
      or m.visibility = 'public'
      or (
        m.visibility = 'circle'
        and exists (
          select 1 from public.connections c
          where c.status = 'accepted'
            and (
              (c.requester_id = auth.uid() and c.target_id = m.user_id)
              or (c.target_id = auth.uid() and c.requester_id = m.user_id)
            )
        )
      )
    )
  order by t.created_at asc;
$$;

grant execute on function public.get_drop_tags(uuid) to authenticated;

-- ─── Realtime + push per la notifica "sei stato taggato" ─────────────────────
-- 1. Abilita Realtime sulla tabella drop_tags (Database → Replication).
-- 2. Registra un Database Webhook su INSERT di drop_tags verso l'edge function
--    send-push, come già fatto per likes/connections/messages (vedi il
--    commento in testa a supabase/functions/send-push/index.ts).

alter publication supabase_realtime add table public.drop_tags;
