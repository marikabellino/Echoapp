-- ============================================================
-- Echo App — Fix: "Taggato in" invisibile su profili altrui
-- Esegui nel SQL Editor di Supabase dopo 020
-- ============================================================

-- getTaggedDrops() interrogava direttamente drop_tags (join a memories via
-- PostgREST), ma la RLS "DropTags: select own" (015_drop_tags.sql) permette
-- la select solo a chi è il taggato o chi ha taggato — quindi chiunque altro
-- guardi il profilo di una terza persona vedeva sempre zero righe, anche se
-- il tag esisteva ed era un drop pubblico. Stessa soluzione già adottata per
-- get_drop_tags: RPC security definer che applica la visibilità del drop
-- (stessa logica di "Memories: read") invece della RLS restrittiva su
-- drop_tags, che deve restare così com'è per l'affidabilità del realtime.

create or replace function public.get_tagged_drops(p_user_id uuid)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(m.*)
      || jsonb_build_object(
           'profiles', jsonb_build_object(
             'id', p.id,
             'username', p.username,
             'display_name', p.display_name,
             'avatar_url', p.avatar_url,
             'memories_count', p.memories_count,
             'connections_count', p.connections_count
           ),
           'event', case when e.id is null then null
                         else jsonb_build_object('id', e.id, 'title', e.title) end
         )
  from public.drop_tags t
  join public.memories m on m.id = t.drop_id
  join public.profiles p on p.id = m.user_id
  left join public.events e on e.id = m.event_id
  where t.tagged_user_id = p_user_id
    and t.hidden_by_tagged = false
    and (
      m.user_id = auth.uid()
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
      or t.tagged_user_id = auth.uid()
    )
  order by t.created_at desc;
$$;

grant execute on function public.get_tagged_drops(uuid) to authenticated;
