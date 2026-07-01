-- The partial unique index from 010 can't be used as an ON CONFLICT target
-- by the upsert in reportUser(). Replace it with a plain unique constraint
-- (NULLs are treated as distinct by unique constraints, so memory reports
-- with reported_user_id = null are unaffected).
drop index if exists public.reports_reporter_reported_user_unique;

alter table public.reports
  add constraint reports_reporter_reported_user_unique
  unique (reporter_id, reported_user_id);
