# Bote-Bakal Tagum

Android app (Flutter) for Tagum City, Philippines, that connects households with bote-bakal (recyclable) collectors.

- **Households** post recyclables with a photo, the types, an estimated weight in kg, a map pin and a For Sale / Free label. They can edit a post until a collector reserves it, search and filter their posts, see past pickups, follow barangays to get alerts about collector routes, and rate the collector after pickup.
- **Collectors** see available posts on a map, filter them by type and by For Sale / Free, and reserve a post so other collectors can't take it. The **Route Guide** puts their reserved pickups in the shortest order from where they are, with distance and time, and hands the trip to Google Maps. The app also shows which barangays have the most posts waiting and suggests where to schedule the next route. They mark posts as collected and schedule routes (date, time, barangays).

The app doesn't handle payment. The price is agreed in person at pickup. Only places inside Tagum City are allowed for now.

Post status: **Available → Reserved → Collected**. A collector can cancel a reservation, which makes the post Available again.

## Sign-in

Sign-in is **Google only**. On the login screen you tap **I'm a Household** or **I'm a Collector**, and Google's one-tap account sheet opens. A new account gets the role you tapped; an existing account keeps its role. Every account has an email Google has already verified, which keeps spam and throwaway accounts out, and nobody has a password to forget. Households are asked for a mobile number once, just before their first post, so collectors can call them.

## Running

```
flutter pub get
flutter run
```

The app always uses the real Supabase backend and reads its keys from **`.env`** (copy `.env.example`). If the keys are missing it shows a *Backend not connected* screen. The tests use an in-memory copy of the backend in `test/support/`.

## Connecting Supabase

### 1. Database
Create a Supabase project, open **SQL Editor**, paste **`supabase/schema.sql`** and run it. It creates the tables, row-level security, triggers, the `post-photos` storage bucket, realtime, and the `complete_profile` / `reserve_post` / `cancel_reservation` / `mark_collected` / `rate_collector` functions.

### 2. Google sign-in
In **Google Cloud Console → APIs & Services → Credentials**:

1. **OAuth consent screen**: set it up (External, app name, support email).
2. **Create OAuth client ID → Web application.** Copy its *Client ID* and *Client secret*.
3. **Create OAuth client ID → Android.** Package name `com.hitchmeup.hitchmeup`, plus the SHA-1 of your signing key:
   ```
   cd android
   ./gradlew signingReport      # use the SHA1 under "Variant: debug"
   ```
   (Add the release key's SHA-1 too before publishing.)

In **Supabase → Authentication → Sign In / Providers → Google**: enable it, paste the **Web** client ID and secret, and save.
If sign-in later fails with a *nonce* error, turn on **Skip nonce check** on the same page.

### 3. `.env`
```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...     # or the legacy anon key
GOOGLE_WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com   # the WEB client, not Android
```
Restart the app (a full restart, not hot reload). `.env` is git-ignored. The publishable key is safe to ship in the app because row-level security protects the data.

### How it's wired
The screens only use the interfaces in **`lib/data/repositories.dart`**. `lib/main.dart` picks the implementation at start-up:

| Interface | Supabase (`lib/data/supabase/`) |
|---|---|
| `AuthRepository` | Google → `auth.signInWithIdToken`, `profiles`, `complete_profile` |
| `PostRepository` | `posts` (realtime), storage `post-photos`, status RPCs |
| `RouteRepository` | `routes` (realtime) |
| `PushService` | not wired yet (FCM + Edge Function later) |

## How the route suggestions work

- **Route Guide** (`lib/route_planner.dart`): tries every visiting order for up to 8 pickups, and uses nearest-neighbour plus 2-opt for more. Distances are straight-line × 1.3 to approximate roads; time assumes about 18 km/h plus 6 minutes per stop. Turn-by-turn directions come from Google Maps, which the collector opens with one button.
- **Busiest barangays**: counts the available posts and kilos per barangay. For "suggested for your next route", a barangay with no collector scheduled yet counts double.

## Project layout

```
lib/
  main.dart                 App start + backend wiring (mock ↔ Supabase)
  config.dart               Reads .env
  constants.dart            Barangays, recyclable types, Tagum map limits
  route_planner.dart        Shortest pickup order + busiest-barangay ranking
  data/repositories.dart    Backend endpoints (interfaces)
  data/supabase/            Supabase implementation
  models/                   AppUser, RecyclablePost, RouteSchedule
  screens/auth/             Role + Google login, first-login role save
  screens/household/        My Posts, Create Post, Routes, Follow Barangays
  screens/collector/        Map with filters, Reserved, Route Guide, Routes,
                            Schedule Route
  screens/common/           Post details and actions
  widgets/                  Shared UI (post card, type colors, kg stepper,
                            barangay picker, route tile, map)
supabase/schema.sql         Database schema for the real backend
```

The map uses OpenStreetMap through `flutter_map`, so it needs no API key.
