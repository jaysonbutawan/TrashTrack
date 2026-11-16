// BACKEND ENDPOINTS
//
// The UI only talks to these interfaces. The app uses the Supabase
// implementation in lib/data/supabase/; the tests use an in-memory one in
// test/support/.
//
// Each method notes the Supabase table / RPC it maps to (supabase/schema.sql).
// Methods that fail should throw [BackendException] with a message that is
// safe to show to the user.

import '../models/app_user.dart';
import '../models/post.dart';
import '../models/route_schedule.dart';

class BackendException implements Exception {
  BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class AuthRepository {
  /// Signed-in user's profile, or null when signed out.
  /// Supabase: `auth.onAuthStateChange` + `profiles` row (realtime).
  Stream<AppUser?> currentUser();

  /// Native Google one-tap account sheet, then `auth.signInWithIdToken`.
  /// Only Google-verified emails can sign in, which keeps out spam accounts.
  ///
  /// [role] is what the user picked on the login screen. A brand-new account
  /// is given that role before this returns (`rpc('complete_profile')`); an
  /// existing account keeps its role, which is returned so the UI can mention
  /// it if it differs. [currentUser] only emits once the account is ready.
  /// Throws [SignInCancelled] if the user closes the sheet.
  Future<UserRole?> signInWithGoogle(UserRole role);

  /// Fallback for an account that still has no role (sign-in was interrupted
  /// half-way): `rpc('complete_profile', {p_role})`.
  Future<void> finishSignUp(UserRole role);

  /// Supabase: `update profiles set phone = ...` (asked before the first post).
  Future<void> updatePhone(String phone);

  /// Profile tab edits. Only the fields given are changed.
  /// Supabase: `update profiles set name/phone/barangay = ... where id = auth.uid()`.
  Future<void> updateProfile({String? name, String? phone, String? barangay});

  /// Supabase: `auth.signOut` (and Google sign-out).
  Future<void> signOut();

  /// Supabase: `update profiles set followed_barangays = ... where id = auth.uid()`.
  Future<void> setFollowedBarangays(List<String> barangays);
}

/// Thrown when the user closes the Google account picker. Not an error.
class SignInCancelled implements Exception {}

abstract class PostRepository {
  /// Supabase: `posts` where `household_id = uid`, newest first (realtime).
  Stream<List<RecyclablePost>> householdPosts(String householdId);

  /// Supabase: `posts` where `status = 'available'` (realtime).
  Stream<List<RecyclablePost>> availablePosts();

  /// Supabase: `posts` where `reserved_by = uid and status = 'reserved'` (realtime).
  Stream<List<RecyclablePost>> reservedBy(String collectorId);

  /// Supabase: single `posts` row by id (realtime); null if deleted.
  Stream<RecyclablePost?> watch(String postId);

  /// Supabase: upload photo to storage bucket `post-photos/{uid}/{uuid}.jpg`,
  /// then insert into `posts`.
  Future<void> create(NewPost post);

  /// Supabase: optional new photo upload, then `update posts` (RLS: owner,
  /// only while available). Fails if a collector reserved it meanwhile.
  Future<void> update(String postId, NewPost post);

  /// Supabase: delete from `posts` (RLS: owner, only while available).
  Future<void> delete(String postId);

  /// Supabase: `rpc('reserve_post', {post_id})` — atomic, fails if taken.
  Future<void> reserve(String postId);

  /// Supabase: `rpc('cancel_reservation', {post_id})`.
  Future<void> cancelReservation(String postId);

  /// Supabase: `rpc('mark_collected', {post_id})`.
  Future<void> markCollected(String postId);

  /// Supabase: `rpc('rate_collector', {post_id, stars})`.
  Future<void> rateCollector(String postId, int stars);

  /// Supabase: view `collector_ratings` (avg + count) for one collector.
  Stream<CollectorRating> collectorRating(String collectorId);
}

abstract class RouteRepository {
  /// Supabase: `routes` where `collector_id = uid and start_time >= today`.
  Stream<List<RouteSchedule>> collectorRoutes(String collectorId);

  /// Supabase: `routes` where `barangays && {list}` (overlap) and upcoming.
  Stream<List<RouteSchedule>> routesFor(List<String> barangays);

  /// Supabase: insert into `routes`. A database webhook / Edge Function then
  /// pushes an alert to households following those barangays.
  /// [puroks] narrows a barangay to some of its puroks (jsonb column
  /// `puroks`); a barangay not in it is visited whole.
  Future<void> schedule({
    required DateTime startTime,
    required List<String> barangays,
    String note = '',
    Map<String, List<String>> puroks = const {},
  });

  /// Supabase: delete from `routes` (RLS: owner only).
  Future<void> delete(String routeId);
}

/// Push alerts for collector routes. With Supabase this is usually FCM
/// (topic per barangay) triggered by an Edge Function; NoopPushService does nothing for now.
abstract class PushService {
  Future<void> requestPermission();
  Future<void> syncFollowedBarangays(List<String> barangays);
  Future<void> clear();
}
