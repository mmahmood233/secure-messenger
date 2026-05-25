-- Run this in Supabase SQL Editor after creating the project.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  username text not null unique,
  display_name text not null,
  photo_url text,
  bio text,
  phone_number text,
  public_key text,
  is_online boolean not null default false,
  last_seen timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.contacts (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  contact_id uuid not null references public.profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, contact_id),
  check (owner_id <> contact_id)
);

create table if not exists public.chats (
  id text primary key,
  participant_ids uuid[] not null,
  last_message text,
  last_message_type text,
  last_message_sender_id uuid,
  last_message_time timestamptz,
  unread_count jsonb not null default '{}'::jsonb,
  encrypted_keys jsonb not null default '{}'::jsonb,
  typing jsonb not null default '{}'::jsonb,
  is_secret boolean not null default false,
  created_at timestamptz not null default now(),
  check (array_length(participant_ids, 1) = 2)
);

create table if not exists public.messages (
  id uuid primary key,
  chat_id text not null references public.chats(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  type text not null check (type in ('text', 'image', 'video', 'audio')),
  status text not null default 'sent' check (status in ('sent', 'delivered', 'read')),
  timestamp timestamptz not null default now(),
  is_edited boolean not null default false,
  is_deleted boolean not null default false,
  media_url text,
  thumbnail_url text
);

create index if not exists profiles_username_idx on public.profiles (username);
create index if not exists chats_participant_ids_idx on public.chats using gin (participant_ids);
create index if not exists messages_chat_timestamp_idx on public.messages (chat_id, timestamp);

alter table public.profiles enable row level security;
alter table public.contacts enable row level security;
alter table public.chats enable row level security;
alter table public.messages enable row level security;

drop policy if exists "profiles readable by signed-in users" on public.profiles;
create policy "profiles readable by signed-in users"
on public.profiles for select
to authenticated
using (true);

drop policy if exists "users insert own profile" on public.profiles;
create policy "users insert own profile"
on public.profiles for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile"
on public.profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "users manage own contacts" on public.contacts;
create policy "users manage own contacts"
on public.contacts for all
to authenticated
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

drop policy if exists "participants read chats" on public.chats;
create policy "participants read chats"
on public.chats for select
to authenticated
using (auth.uid() = any(participant_ids));

drop policy if exists "participants create chats" on public.chats;
create policy "participants create chats"
on public.chats for insert
to authenticated
with check (auth.uid() = any(participant_ids));

drop policy if exists "participants update chats" on public.chats;
create policy "participants update chats"
on public.chats for update
to authenticated
using (auth.uid() = any(participant_ids))
with check (auth.uid() = any(participant_ids));

drop policy if exists "participants read messages" on public.messages;
create policy "participants read messages"
on public.messages for select
to authenticated
using (
  exists (
    select 1 from public.chats
    where chats.id = messages.chat_id
      and auth.uid() = any(chats.participant_ids)
  )
);

drop policy if exists "participants send messages" on public.messages;
create policy "participants send messages"
on public.messages for insert
to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1 from public.chats
    where chats.id = messages.chat_id
      and auth.uid() = any(chats.participant_ids)
  )
);

drop policy if exists "participants update messages" on public.messages;
create policy "participants update messages"
on public.messages for update
to authenticated
using (
  exists (
    select 1 from public.chats
    where chats.id = messages.chat_id
      and auth.uid() = any(chats.participant_ids)
  )
)
with check (
  exists (
    select 1 from public.chats
    where chats.id = messages.chat_id
      and auth.uid() = any(chats.participant_ids)
  )
);

insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do update set public = false;

drop policy if exists "profile photos readable" on storage.objects;
create policy "profile photos readable"
on storage.objects for select
to authenticated
using (bucket_id = 'profile-photos');

drop policy if exists "users manage own profile photo" on storage.objects;
create policy "users manage own profile photo"
on storage.objects for all
to authenticated
using (bucket_id = 'profile-photos' and name = auth.uid()::text || '.jpg')
with check (bucket_id = 'profile-photos' and name = auth.uid()::text || '.jpg');

drop policy if exists "chat media participant access" on storage.objects;
create policy "chat media participant access"
on storage.objects for all
to authenticated
using (
  bucket_id = 'chat-media'
  and exists (
    select 1 from public.chats
    where chats.id = split_part(storage.objects.name, '/', 1)
      and auth.uid() = any(chats.participant_ids)
  )
)
with check (
  bucket_id = 'chat-media'
  and exists (
    select 1 from public.chats
    where chats.id = split_part(storage.objects.name, '/', 1)
      and auth.uid() = any(chats.participant_ids)
  )
);
