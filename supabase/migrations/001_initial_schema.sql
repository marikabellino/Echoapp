-- ============================================================
-- Echo App — Schema iniziale
-- Esegui questo script nel SQL Editor del tuo progetto Supabase
-- ============================================================

-- ─── Profiles ────────────────────────────────────────────────────────────────

create table if not exists public.profiles (
  id              uuid references auth.users on delete cascade primary key,
  username        text unique not null,
  display_name    text not null default '',
  bio             text not null default '',
  avatar_url      text,
  memories_count  integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ─── Memories ────────────────────────────────────────────────────────────────

create table if not exists public.memories (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references public.profiles(id) on delete cascade not null,
  description     text not null,
  mood            text not null check (mood in ('echo','love','secret','dream','lost')),
  latitude        double precision not null,
  longitude       double precision not null,
  location_name   text,
  image_url       text,
  ai_caption      text,
  likes_count     integer not null default 0,
  is_public       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Indice per query geografiche (bounding box)
create index if not exists memories_lat_idx on public.memories (latitude);
create index if not exists memories_lng_idx on public.memories (longitude);
create index if not exists memories_user_idx on public.memories (user_id);
create index if not exists memories_created_idx on public.memories (created_at desc);

-- ─── Likes ───────────────────────────────────────────────────────────────────

create table if not exists public.likes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  memory_id   uuid references public.memories(id) on delete cascade not null,
  created_at  timestamptz not null default now(),
  unique (user_id, memory_id)
);

-- ─── Comments ────────────────────────────────────────────────────────────────

create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  memory_id   uuid references public.memories(id) on delete cascade not null,
  content     text not null,
  created_at  timestamptz not null default now()
);

-- ─── Row Level Security ───────────────────────────────────────────────────────

alter table public.profiles  enable row level security;
alter table public.memories  enable row level security;
alter table public.likes     enable row level security;
alter table public.comments  enable row level security;

-- Profiles
create policy "Profiles: public read"
  on public.profiles for select using (true);
create policy "Profiles: self insert"
  on public.profiles for insert with check (auth.uid() = id);
create policy "Profiles: self update"
  on public.profiles for update using (auth.uid() = id);

-- Memories
create policy "Memories: public read"
  on public.memories for select
  using (is_public = true or auth.uid() = user_id);
create policy "Memories: auth insert"
  on public.memories for insert with check (auth.uid() = user_id);
create policy "Memories: self update"
  on public.memories for update using (auth.uid() = user_id);
create policy "Memories: self delete"
  on public.memories for delete using (auth.uid() = user_id);

-- Likes
create policy "Likes: public read"
  on public.likes for select using (true);
create policy "Likes: auth insert"
  on public.likes for insert with check (auth.uid() = user_id);
create policy "Likes: self delete"
  on public.likes for delete using (auth.uid() = user_id);

-- Comments
create policy "Comments: public read"
  on public.comments for select using (true);
create policy "Comments: auth insert"
  on public.comments for insert with check (auth.uid() = user_id);
create policy "Comments: self delete"
  on public.comments for delete using (auth.uid() = user_id);

-- ─── Storage Buckets ─────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
  values ('memories', 'memories', true)
  on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

create policy "Storage memories: public read"
  on storage.objects for select using (bucket_id = 'memories');
create policy "Storage memories: auth upload"
  on storage.objects for insert
  with check (bucket_id = 'memories' and auth.role() = 'authenticated');

create policy "Storage avatars: public read"
  on storage.objects for select using (bucket_id = 'avatars');
create policy "Storage avatars: auth upload"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and auth.role() = 'authenticated');
create policy "Storage avatars: self update"
  on storage.objects for update
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- ─── Triggers ────────────────────────────────────────────────────────────────

-- Crea automaticamente il profilo al signup
create or replace function public.on_auth_user_created()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'username',
      split_part(new.email, '@', 1)
    ),
    coalesce(
      new.raw_user_meta_data->>'display_name',
      new.raw_user_meta_data->>'username',
      split_part(new.email, '@', 1)
    )
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.on_auth_user_created();

-- Aggiorna likes_count quando viene aggiunto/rimosso un like
create or replace function public.on_like_inserted()
returns trigger language plpgsql security definer as $$
begin
  update public.memories
  set likes_count = likes_count + 1
  where id = new.memory_id;
  return new;
end;
$$;

create or replace function public.on_like_deleted()
returns trigger language plpgsql security definer as $$
begin
  update public.memories
  set likes_count = greatest(0, likes_count - 1)
  where id = old.memory_id;
  return old;
end;
$$;

drop trigger if exists on_like_inserted on public.likes;
create trigger on_like_inserted
  after insert on public.likes
  for each row execute function public.on_like_inserted();

drop trigger if exists on_like_deleted on public.likes;
create trigger on_like_deleted
  after delete on public.likes
  for each row execute function public.on_like_deleted();

-- Aggiorna memories_count sul profilo
create or replace function public.on_memory_inserted()
returns trigger language plpgsql security definer as $$
begin
  update public.profiles
  set memories_count = memories_count + 1
  where id = new.user_id;
  return new;
end;
$$;

create or replace function public.on_memory_deleted()
returns trigger language plpgsql security definer as $$
begin
  update public.profiles
  set memories_count = greatest(0, memories_count - 1)
  where id = old.user_id;
  return old;
end;
$$;

drop trigger if exists on_memory_inserted on public.memories;
create trigger on_memory_inserted
  after insert on public.memories
  for each row execute function public.on_memory_inserted();

drop trigger if exists on_memory_deleted on public.memories;
create trigger on_memory_deleted
  after delete on public.memories
  for each row execute function public.on_memory_deleted();
