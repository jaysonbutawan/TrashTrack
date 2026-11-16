-- Bote-Bakal Tagum — Supabase schema
-- Run once in the Supabase SQL editor on a new project. Matches the endpoints
-- in lib/data/repositories.dart and the column names read by the models'
-- fromMap() in lib/models/.

-- ───────────────────────── profiles ─────────────────────────
-- One row per Google account. `role` stays NULL until the app saves the
-- role picked on the login screen (complete_profile below).
create table public.profiles (
  id                 uuid primary key references auth.users on delete cascade,
  name               text not null default '',
  phone              text not null default '',
  email              text not null default '',
  avatar_url         text not null default '',
  role               text check (role in ('household', 'collector')),
  barangay           text not null default '',   -- household's home barangay
  followed_barangays text[] not null default '{}',
  created_at         timestamptz not null default now()
);

-- Create the profile from the Google account on first sign-in.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture', '')
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
  household_name   text not null,   -- filled by trigger from profiles
  household_phone  text not null,   -- filled by trigger from profiles
  photo_url        text not null default '',
  types            text[] not null check (cardinality(types) > 0),
  weight_kg        numeric(5,1) not null check (weight_kg > 0 and weight_kg <= 500),
  -- Tagum City only (keep in sync with lib/constants.dart)
  lat              double precision not null check (lat between 7.33 and 7.58),
  lng              double precision not null check (lng between 125.68 and 125.93),
  barangay         text not null,
  purok            text not null default '' check (length(purok) <= 60),
  -- why the last collector cancelled; shown to the household
  cancel_reason    text not null default '',
  label            text not null check (label in ('for_sale', 'free')),
  status           text not null default 'available'
                   check (status in ('available', 'reserved', 'collected')),
  notes            text not null default '' check (length(notes) <= 300),
  reserved_by      uuid references public.profiles,
  reserved_by_name text,
  reserved_at      timestamptz,
  collected_at     timestamptz,
  rating           smallint check (rating between 1 and 5),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index posts_status_idx      on public.posts (status);
create index posts_household_idx   on public.posts (household_id);
create index posts_reserved_by_idx on public.posts (reserved_by);

-- The app never sends name/phone; copy them from the poster's profile.
create function public.fill_post_household() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select name, phone into new.household_name, new.household_phone
    from profiles where id = new.household_id;
  return new;
end $$;

create trigger posts_fill_household
  before insert on public.posts
  for each row execute function public.fill_post_household();

create function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger posts_touch
  before update on public.posts
  for each row execute function public.touch_updated_at();

-- ───────────────────────── routes ─────────────────────────
create table public.routes (
  id             uuid primary key default gen_random_uuid(),
  collector_id   uuid not null references public.profiles on delete cascade,
  collector_name text not null,     -- filled by trigger from profiles
  start_time     timestamptz not null,
  barangays      text[] not null check (cardinality(barangays) > 0),
  note           text not null default '',
  -- {"Apokon": ["Purok 1", "Purok 3"]}; a barangay not listed = whole barangay
  puroks         jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);

create index routes_barangays_idx on public.routes using gin (barangays);
create index routes_start_idx     on public.routes (start_time);

create function public.fill_route_collector() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select name into new.collector_name from profiles where id = new.collector_id;
  return new;
end $$;

create trigger routes_fill_collector
  before insert on public.routes
  for each row execute function public.fill_route_collector();

-- ───────────────────────── ratings view ─────────────────────────
-- Runs as its owner so everyone sees riders' averages, even though other
-- people's reserved/collected posts are private.
create view public.collector_ratings
with (security_invoker = false) as
  select reserved_by as collector_id,
         avg(rating)::float as average,
         count(rating)      as count
  from public.posts
  where rating is not null
  group by reserved_by;
grant select on public.collector_ratings to authenticated;

-- ───────────────────────── helpers ─────────────────────────
create function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- First sign-in: save the role picked on the login screen. Works only once.
-- (The mobile number is asked later, before a household's first post.)
create function public.complete_profile(p_role text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_role not in ('household', 'collector') then
    raise exception 'Please choose Household or Collector.';
  end if;
  update profiles set role = p_role
   where id = auth.uid() and role is null;
  if not found then
    raise exception 'Your account is already set up.';
  end if;
end $$;

-- ───────────────────────── row level security ─────────────────────────
alter table public.profiles enable row level security;
alter table public.posts    enable row level security;
alter table public.routes   enable row level security;

create policy "profiles readable by signed-in users"
  on public.profiles for select to authenticated using (true);
create policy "users update own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
-- Role is set only through complete_profile(); users may edit the rest.
revoke update on public.profiles from authenticated, anon;
grant update (name, phone, barangay, followed_barangays) on public.profiles to authenticated;

-- Reserved/collected posts are private to the household and the collector
-- who reserved; available ones (incl. cancelled) are visible to everyone.
create policy "posts readable when available or involved"
  on public.posts for select to authenticated
  using (status = 'available'
         or household_id = auth.uid()
         or reserved_by = auth.uid());
create policy "households create own available posts"
  on public.posts for insert to authenticated
  with check (household_id = auth.uid() and public.my_role() = 'household'
              and status = 'available' and reserved_by is null and rating is null);
-- Owners may edit while no collector has reserved the post. Only the content
-- columns are granted, so status/reservation/rating still go through the RPCs.
create policy "households edit own available posts"
  on public.posts for update to authenticated
  using (household_id = auth.uid() and status = 'available')
  with check (household_id = auth.uid() and status = 'available');
revoke update on public.posts from authenticated, anon;
grant update (photo_url, types, weight_kg, lat, lng, barangay, purok, label,
              notes)
  on public.posts to authenticated;
create policy "households delete own available posts"
  on public.posts for delete to authenticated
  using (household_id = auth.uid() and status = 'available');

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
  if public.my_role() is distinct from 'collector' then
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

create function public.cancel_reservation(post_id uuid, reason text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  update posts set status = 'available', reserved_by = null,
                   reserved_by_name = null, reserved_at = null,
                   cancel_reason = left(coalesce(trim(reason), ''), 120)
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
  public.mark_collected, public.rate_collector, public.complete_profile
  from anon, public;
grant execute on function public.reserve_post, public.cancel_reservation,
  public.mark_collected, public.rate_collector, public.complete_profile
  to authenticated;

-- ───────────────────────── realtime ─────────────────────────
alter publication supabase_realtime add table public.posts, public.routes, public.profiles;
-- Full rows in UPDATE/DELETE events, so filtered streams see them.
alter table public.posts  replica identity full;
alter table public.routes replica identity full;

-- ───────────────────────── storage ─────────────────────────
-- Public bucket for post photos, path: post-photos/{user_id}/{file}.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-photos', 'post-photos', true, 5242880, array['image/jpeg', 'image/png']);

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
