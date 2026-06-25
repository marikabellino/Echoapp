create table if not exists public.reports (
  id            uuid        primary key default gen_random_uuid(),
  reporter_id   uuid        not null references public.profiles(id) on delete cascade,
  memory_id     uuid        not null references public.memories(id) on delete cascade,
  created_at    timestamptz not null default now(),
  unique (reporter_id, memory_id)
);

alter table public.reports enable row level security;

-- Only the reporter can insert their own report
create policy "Users can insert their own reports"
  on public.reports for insert
  to authenticated
  with check (reporter_id = auth.uid());

-- Only the reporter can read their own reports
create policy "Users can read their own reports"
  on public.reports for select
  to authenticated
  using (reporter_id = auth.uid());
