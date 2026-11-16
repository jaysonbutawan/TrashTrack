-- Post Recyclables: households choose the purok inside their barangay so
-- collectors can find the house (Tagum barangays are large).
alter table public.posts
  add column if not exists purok text not null default ''
  check (length(purok) <= 60);

-- Households may edit it like the other post fields.
revoke update on public.posts from authenticated, anon;
grant update (photo_url, types, weight_kg, lat, lng, barangay, purok, label,
              notes)
  on public.posts to authenticated;
