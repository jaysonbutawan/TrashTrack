-- Bote-Bakal Tagum — Supabase schema
-- Run in the Supabase SQL editor. Matches the endpoints in lib/data/repositories.dart
-- and the column names read by the models' fromMap() in lib/models/.

-- ───────────────────────── profiles ─────────────────────────
create table public.profiles (
  id                 uuid primary key references auth.users on delete cascade,
  name               text not null,
  phone              text not null,
  role               text not null check (role in ('household', 'collector')),
  followed_barangays text[] not null default '{}',
  created_at         timestamptz not null default now()
);

-- Create the profile from sign-up metadata: auth.signUp(data: {name, phone, role}).
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, phone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'role', 'household')
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── posts ─────────────────────────
create table public.posts (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references public.profiles on delete cascade,
  household_name   text not null,
  household_phone  text not null,
  photo_url        text not null default '',
  types            text[] not null check (cardinality(types) > 0),
  amount           text not null,
  -- Tagum City only (keep in sync with lib/constants.dart)
  lat              double precision not null check (lat between 7.33 and 7.58),
  lng              double precision not null check (lng between 125.68 and 125.93),
  barangay         text not null,
  label            text not null check (label in ('for_sale', 'free')),
  status           text not null default 'available'
                   check (status in ('available', 'reserved', 'collected')),
  notes            text not null default '',
  reserved_by      uuid references public.profiles,
  reserved_by_name text,
  reserved_at      timestamptz,
  collected_at     timestamptz,
  rating           smallint check (rating between 1 and 5),
  created_at       timestamptz not null default now()
);

create index posts_status_idx      on public.posts (status);
create index posts_household_idx   on public.posts (household_id);
create index posts_reserved_by_idx on public.posts (reserved_by);

-- ───────────────────────── routes ─────────────────────────
create table public.routes (
  id             uuid primary key default gen_random_uuid(),
  collector_id   uuid not null references public.profiles on delete cascade,
  collector_name text not null,
  start_time     timestamptz not null,
  barangays      text[] not null check (cardinality(barangays) > 0),
  note           text not null default '',
  created_at     timestamptz not null default now()
);

create index routes_barangays_idx on public.routes using gin (barangays);
create index routes_start_idx     on public.routes (start_time);

-- ───────────────────────── ratings view ─────────────────────────
create view public.collector_ratings
with (security_invoker = true) as
  select reserved_by as collector_id,
         avg(rating)::float as average,
         count(rating)      as count
  from public.posts
  where rating is not null
  group by reserved_by;

-- ───────────────────────── helpers ─────────────────────────
create function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- ───────────────────────── row level security ─────────────────────────
alter table public.profiles enable row level security;
alter table public.posts    enable row level security;
alter table public.routes   enable row level security;

create policy "profiles readable by signed-in users"
  on public.profiles for select to authenticated using (true);
create policy "users update own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.my_role());

create policy "posts readable by signed-in users"
  on public.posts for select to authenticated using (true);
create policy "households create own available posts"
  on public.posts for insert to authenticated
  with check (household_id = auth.uid() and public.my_role() = 'household'
              and status = 'available' and reserved_by is null and rating is null);
create policy "households delete own available posts"
  on public.posts for delete to authenticated
  using (household_id = auth.uid() and status = 'available');
-- No direct UPDATE policy: status changes and ratings go through the RPCs below.

create policy "routes readable by signed-in users"
  on public.routes for select to authenticated using (true);
create policy "collectors create own routes"
  on public.routes for insert to authenticated
  with check (collector_id = auth.uid() and public.my_role() = 'collector');
create policy "collectors delete own routes"
  on public.routes for delete to authenticated
  using (collector_id = auth.uid());

-- ───────────────────────── status RPCs (atomic) ─────────────────────────
-- Each UPDATE only matches when the post is in the expected state, so two
-- collectors can never reserve the same post.

create function public.reserve_post(post_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() <> 'collector' then
    raise exception 'Only collectors can reserve.';
  end if;
  update posts set status = 'reserved',
                   reserved_by = auth.uid(),
                   reserved_by_name = (select name from profiles where id = auth.uid()),
                   reserved_at = now()
   where id = post_id and status = 'available';
  if not found then
    raise exception 'Sorry, another collector already reserved this.';
  end if;
end $$;

create function public.cancel_reservation(post_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update posts set status = 'available', reserved_by = null,
                   reserved_by_name = null, reserved_at = null
   where id = post_id and status = 'reserved' and reserved_by = auth.uid();
  if not found then
    raise exception 'You can no longer cancel this.';
  end if;
end $$;

create function public.mark_collected(post_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update posts set status = 'collected', collected_at = now()
   where id = post_id and status = 'reserved' and reserved_by = auth.uid();
  if not found then
    raise exception 'Only the collector who reserved this can mark it collected.';
  end if;
end $$;

create function public.rate_collector(post_id uuid, stars int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if stars < 1 or stars > 5 then
    raise exception 'Rating must be 1 to 5 stars.';
  end if;
  update posts set rating = stars
   where id = post_id and household_id = auth.uid()
     and status = 'collected' and rating is null;
  if not found then
    raise exception 'You can rate only once, after pickup.';
  end if;
end $$;

revoke execute on function public.reserve_post, public.cancel_reservation,
  public.mark_collected, public.rate_collector from anon;

-- ───────────────────────── realtime ─────────────────────────
alter publication supabase_realtime add table public.posts, public.routes, public.profiles;

-- ───────────────────────── storage ─────────────────────────
-- Public bucket for post photos, path: post-photos/{user_id}/{file}.jpg
insert into storage.buckets (id, name, public) values ('post-photos', 'post-photos', true);

create policy "users upload own post photos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'post-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "users delete own post photos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'post-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ───────────────────────── route alerts (later) ─────────────────────────
-- Add a Database Webhook on INSERT into public.routes that calls an Edge
-- Function. The function sends a push (e.g. FCM topic per barangay) to
-- households whose profiles.followed_barangays overlap routes.barangays.
