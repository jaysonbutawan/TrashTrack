# Bote-Bakal Tagum

Android app (Flutter) for Tagum City, Philippines, that connects households with bote-bakal (recyclable) collectors.

- **Households** post recyclables with a photo, the types, an estimated amount, a map pin and a For Sale / Free label. They follow barangays to get alerts about collector routes, and they rate the collector after pickup.
- **Collectors** see available posts on a map, filter them by type and by For Sale / Free, and reserve a post so other collectors can't take it. They mark posts as collected and schedule routes (date, time, barangays).

The app doesn't handle payment. The price is agreed in person at pickup. Only places inside Tagum City are allowed for now.

Post status: **Available → Reserved → Collected**. A collector can cancel a reservation, which makes the post Available again.

## Current state: UI on static data

There is no backend yet. The app runs on sample data kept in memory (`lib/data/mock/`), so every screen can be tried and designed. Changes you make while using it (posting, reserving, rating) last until you restart the app.

Demo logins (or tap **Try the demo** on the login screen):

| Role | Email | Password |
|---|---|---|
| Household | `household@demo.ph` | `demo123` |
| Collector | `collector@demo.ph` | `demo123` |

Run on the build machine (Windows, with the Android SDK):

```
flutter pub get
flutter run
```

## Connecting Supabase later

The screens never call a backend directly. They only use the interfaces in **`lib/data/repositories.dart`**, which are the backend endpoints:

| Interface | What it does | Supabase |
|---|---|---|
| `AuthRepository` | sign in/up/out, current profile, follow barangays | `auth`, `profiles` |
| `PostRepository` | list/watch/create/delete posts, reserve, cancel, collect, rate | `posts`, storage `post-photos`, RPCs |
| `RouteRepository` | schedule/list/delete collector routes | `routes` |
| `PushService` | route alerts on this phone | FCM + Edge Function |

Steps:
1. Create a Supabase project and run **`supabase/schema.sql`** in the SQL editor. It creates the tables, the security rules (RLS), the storage bucket, realtime, and the atomic `reserve_post` / `cancel_reservation` / `mark_collected` / `rate_collector` functions.
2. `flutter pub add supabase_flutter`
3. Write `lib/data/supabase/…` classes that implement the four interfaces. Each method in `repositories.dart` has a comment naming the table or RPC it maps to. The models already have `fromMap()` with matching column names. For example:
   ```dart
   @override
   Stream<List<RecyclablePost>> availablePosts() => supabase
       .from('posts')
       .stream(primaryKey: ['id'])
       .eq('status', 'available')
       .map((rows) => rows.map(RecyclablePost.fromMap).toList());

   @override
   Future<void> reserve(String postId) async {
     try {
       await supabase.rpc('reserve_post', params: {'post_id': postId});
     } on PostgrestException catch (e) {
       throw BackendException(e.message); // shown to the user as-is
     }
   }
   ```
4. In `lib/main.dart`, call `Supabase.initialize(...)` and swap the four `Mock…` objects for the Supabase ones. No screen code changes.

## Project layout

```
lib/
  main.dart                 App start + backend wiring (mock ↔ Supabase)
  constants.dart            Barangays, recyclable types, Tagum map limits
  data/repositories.dart    Backend endpoints (interfaces)
  data/mock/                Static demo data + in-memory implementation
  models/                   AppUser, RecyclablePost, RouteSchedule
  screens/auth/             Login, Register (choose Household or Collector)
  screens/household/        My Posts, Create Post, Routes, Follow Barangays
  screens/collector/        Map with filters, Reserved, Routes, Schedule Route
  screens/common/           Post details and actions
  widgets/                  Shared UI (big buttons, status labels, map)
supabase/schema.sql         Database schema for the real backend
```

The map uses OpenStreetMap through `flutter_map`, so it needs no API key.
