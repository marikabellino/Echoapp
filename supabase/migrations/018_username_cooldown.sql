-- ============================================================
-- Echo App — Cooldown di 30 giorni per il cambio username
-- Esegui nel SQL Editor di Supabase dopo 017
-- ============================================================

-- Traccia quando l'username è stato cambiato l'ultima volta. Null = mai
-- cambiato dalla registrazione, quindi il primo cambio è sempre permesso.
alter table public.profiles
  add column if not exists username_changed_at timestamptz;

-- Applicato in un trigger (non solo lato client) perché è l'unico punto che
-- vede sia il valore vecchio che quello nuovo per ogni update, a prescindere
-- da quale client/percorso esegue la scrittura.
create or replace function public.enforce_username_cooldown()
returns trigger
language plpgsql
as $$
begin
  if new.username is distinct from old.username then
    if old.username_changed_at is not null
       and old.username_changed_at > now() - interval '30 days' then
      raise exception 'Puoi cambiare username una volta ogni 30 giorni.';
    end if;
    new.username_changed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_username_cooldown on public.profiles;

create trigger profiles_username_cooldown
  before update on public.profiles
  for each row
  execute function public.enforce_username_cooldown();
