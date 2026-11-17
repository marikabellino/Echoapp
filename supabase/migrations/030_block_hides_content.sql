create or replace function public.is_blocked_pair(other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocked_users b
    where (b.blocker_id = auth.uid() and b.blocked_id = other)
       or (b.blocker_id = other and b.blocked_id = auth.uid())
  );
$$;

grant execute on function public.is_blocked_pair(uuid) to authenticated;

drop policy if exists "Memories: read" on public.memories;

create policy "Memories: read"
  on public.memories for select
  using (
    auth.uid() = user_id
    or (
      not public.is_blocked_pair(user_id)
      and (
        visibility = 'public'
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
      )
    )
  );

drop policy if exists "Comments: read if drop visible" on public.comments;

create policy "Comments: read if drop visible"
  on public.comments for select
  using (
    exists (select 1 from public.memories m where m.id = memory_id)
    and (auth.uid() = user_id or not public.is_blocked_pair(user_id))
  );

drop policy if exists "Likes: read if drop visible" on public.likes;

create policy "Likes: read if drop visible"
  on public.likes for select
  using (
    exists (select 1 from public.memories m where m.id = memory_id)
    and (auth.uid() = user_id or not public.is_blocked_pair(user_id))
  );

drop policy if exists "Comments: auth insert" on public.comments;
create policy "Comments: auth insert"
  on public.comments for insert
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.memories m where m.id = memory_id)
  );

drop policy if exists "Likes: auth insert" on public.likes;
create policy "Likes: auth insert"
  on public.likes for insert
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.memories m where m.id = memory_id)
  );
