-- ============================================================
-- Echo App — Fix: "column reference tagged_user_id is ambiguous"
-- Esegui nel SQL Editor di Supabase dopo 021
-- ============================================================

-- tag_users_on_drop (019) ha `returns table (tagged_user_id uuid)`: PL/pgSQL
-- crea automaticamente una variabile di output con quel nome, che collide
-- con la colonna reale drop_tags.tagged_user_id usata nella insert/on
-- conflict/returning qui sotto — Postgres non sa più a quale dei due si
-- riferisce e lancia "column reference tagged_user_id is ambiguous".
-- #variable_conflict use_column dice esplicitamente al parser di preferire
-- sempre la colonna della tabella quando c'è ambiguità con una variabile.

drop function if exists public.tag_users_on_drop(uuid, uuid[]);

create function public.tag_users_on_drop(p_drop_id uuid, p_user_ids uuid[])
returns table (tagged_user_id uuid)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if not exists (
    select 1 from public.memories m
    where m.id = p_drop_id and m.user_id = auth.uid()
  ) then
    raise exception 'not_owner';
  end if;

  return query
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
  on conflict (drop_id, tagged_user_id) do nothing
  returning drop_tags.tagged_user_id;
end;
$$;

grant execute on function public.tag_users_on_drop(uuid, uuid[]) to authenticated;
