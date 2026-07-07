-- ============================================================
-- Echo App — tag_users_on_drop ritorna chi è stato taggato davvero
-- Esegui nel SQL Editor di Supabase dopo 018
-- ============================================================

-- Prima la RPC non ritornava nulla: se una persona non era nella cerchia
-- accettata del tagger (o bloccata), veniva scartata dall'insert senza che il
-- client se ne accorgesse — "taggo qualcuno ma non compare da nessuna parte"
-- senza alcun errore visibile. Ora ritorna gli id effettivamente taggati, così
-- il client può segnalare chi è stato scartato e perché.

drop function if exists public.tag_users_on_drop(uuid, uuid[]);

create function public.tag_users_on_drop(p_drop_id uuid, p_user_ids uuid[])
returns table (tagged_user_id uuid)
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
