-- Schedule a Route: collectors can narrow each barangay to some puroks,
-- since Tagum barangays are large. {"Apokon": ["Purok 1", "Purok 3"]};
-- a barangay missing from the map means the whole barangay.
alter table public.routes
  add column if not exists puroks jsonb not null default '{}'::jsonb;
