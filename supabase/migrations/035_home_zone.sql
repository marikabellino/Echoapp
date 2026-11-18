-- ============================================================
-- mingle. — Zona casa: drop lasciati a casa senza rivelare dove abiti
-- Esegui nel SQL Editor di Supabase dopo 034
-- ============================================================
--
-- La posizione di casa NON sta nel database: resta solo sul telefono
-- dell'utente. Al database arriva soltanto un'informazione: "questo drop è
-- stato lasciato a casa" (at_home = true). Da lì il database garantisce,
-- anche se l'app sbagliasse:
--   - mai pubblico: un drop a casa è "cerchia" o "solo io";
--   - nessun punto esatto: le coordinate vengono arrotondate a ~1 km;
--   - nessuna via: il nome del luogo diventa semplicemente "A casa";
--   - niente eventi: un drop di un evento sta nel locale, non a casa.

alter table public.memories
  add column if not exists at_home boolean not null default false;

create index if not exists memories_at_home_idx on public.memories (at_home);

create or replace function public.protect_home_drop()
returns trigger
language plpgsql
as $$
begin
  if new.at_home then
    new.event_id := null;
    if new.visibility = 'public' then
      new.visibility := 'circle';
    end if;
    -- ~1,1 km di precisione: abbastanza per dire "in città", mai l'indirizzo.
    new.latitude := round(new.latitude::numeric, 2)::double precision;
    new.longitude := round(new.longitude::numeric, 2)::double precision;
    new.location_name := 'A casa';
  end if;
  return new;
end;
$$;

-- Il nome "memories_0_..." fa partire questo trigger prima di quello degli
-- eventi (i trigger BEFORE girano in ordine alfabetico).
drop trigger if exists memories_0_protect_home on public.memories;
create trigger memories_0_protect_home
  before insert or update on public.memories
  for each row execute function public.protect_home_drop();

-- Un drop non può "smettere" di essere a casa: altrimenti tornerebbe
-- pubblicabile con coordinate che, arrotondate, sembrerebbero comunque vere.
create or replace function public.keep_home_flag()
returns trigger
language plpgsql
as $$
begin
  if old.at_home and not new.at_home then
    new.at_home := true;
  end if;
  return new;
end;
$$;

drop trigger if exists memories_0_keep_home_flag on public.memories;
create trigger memories_0_keep_home_flag
  before update of at_home on public.memories
  for each row execute function public.keep_home_flag();
