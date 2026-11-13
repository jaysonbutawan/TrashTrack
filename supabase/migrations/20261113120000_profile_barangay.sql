-- Profile tab: households pick the barangay they live in; everyone can edit
-- their name and mobile number.
alter table public.profiles
  add column if not exists barangay text not null default '';

revoke update on public.profiles from authenticated, anon;
grant update (name, phone, barangay, followed_barangays)
  on public.profiles to authenticated;
