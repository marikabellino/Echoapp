-- Allow reporting a user directly (not just a memory).
alter table public.reports
  alter column memory_id drop not null,
  add column if not exists reported_user_id uuid references public.profiles(id) on delete cascade;

alter table public.reports
  add constraint reports_target_check
  check (
    (memory_id is not null and reported_user_id is null)
    or (memory_id is null and reported_user_id is not null)
  );

create unique index if not exists reports_reporter_reported_user_unique
  on public.reports (reporter_id, reported_user_id)
  where reported_user_id is not null;
