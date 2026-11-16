-- Reserved and collected posts are private: only the household who posted
-- and the collector who reserved can read them (name, phone, location).
-- Available posts — including ones a collector cancelled — stay visible to
-- every signed-in user so collectors can find them.
drop policy if exists "posts readable by signed-in users" on public.posts;
drop policy if exists "posts readable when available or involved" on public.posts;
create policy "posts readable when available or involved"
  on public.posts for select to authenticated
  using (status = 'available'
         or household_id = auth.uid()
         or reserved_by = auth.uid());

-- Realtime UPDATE/DELETE events carry every column, so filtered streams
-- (e.g. a collector's own routes) see deletes and status changes.
alter table public.posts  replica identity full;
alter table public.routes replica identity full;

-- Star ratings stay public as averages only, even though other people's
-- posts are no longer readable: the view runs as its owner.
create or replace view public.collector_ratings
with (security_invoker = false) as
  select reserved_by as collector_id,
         avg(rating)::float as average,
         count(rating)      as count
  from public.posts
  where rating is not null
  group by reserved_by;

grant select on public.collector_ratings to authenticated;
