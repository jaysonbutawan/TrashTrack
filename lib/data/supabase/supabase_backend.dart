// Supabase implementation of the backend endpoints in ../repositories.dart.
// Tables, security rules and RPCs are defined in supabase/schema.sql.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../models/route_schedule.dart';
import '../repositories.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Runs a request and turns Supabase errors into [BackendException]s whose
/// message is safe to show (RPCs raise plain-language messages).
Future<T> _guard<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on PostgrestException catch (e) {
    throw BackendException(e.message);
  } on StorageException catch (e) {
    throw BackendException('Photo upload failed: ${e.message}');
  } on AuthException catch (e) {
    throw BackendException(e.message);
  }
}

bool _isUpcoming(RouteSchedule r) {
  final now = DateTime.now();
  return !r.startTime.isBefore(DateTime(now.year, now.month, now.day));
}

// ───────────────────────────── auth ─────────────────────────────

class SupabaseAuthRepository extends AuthRepository {
  SupabaseAuthRepository({required this.googleWebClientId, this.cache});

  final String googleWebClientId;

  /// Phone storage for the last known profile, so a returning user opens
  /// straight to their home screen while the fresh copy loads.
  final SharedPreferences? cache;
  static const _cacheKey = 'profile';

  void _remember(Map<String, dynamic> row) {
    _latestProfile = row;
    cache?.setString(_cacheKey, jsonEncode(row));
  }

  Map<String, dynamic>? _cachedProfile(String id) {
    try {
      final row = jsonDecode(cache?.getString(_cacheKey) ?? 'null');
      // Only a finished account of this same user is worth showing early.
      if (row is Map<String, dynamic> &&
          row['id'] == id &&
          row['role'] != null) {
        return row;
      }
    } catch (_) {}
    return null;
  }

  Future<void>? _googleReady;

  GoTrueClient get _auth => _db.auth;

  /// Latest `profiles` row seen for the signed-in user.
  Map<String, dynamic>? _latestProfile;

  /// True while [signInWithGoogle] runs. Profile updates are held back until
  /// it finishes, so the app goes from the login screen straight to a
  /// ready account instead of flashing a half-set-up one.
  bool _signingIn = false;

  /// Sends [_latestProfile] to whoever listens to [currentUser].
  void Function()? _flush;

  @override
  Stream<AppUser?> currentUser() {
    late final StreamController<AppUser?> out;
    StreamSubscription<AuthState>? authSub;
    StreamSubscription<List<Map<String, dynamic>>>? profileSub;
    String? watchingId;
    // False until the first state is emitted — "signed out" must be emitted
    // too, even though its id (null) equals the initial watchingId.
    var started = false;

    void follow(Session? session) {
      final id = session?.user.id;
      if (started && id == watchingId) return;
      started = true;
      watchingId = id;
      profileSub?.cancel();
      profileSub = null;
      if (_latestProfile?['id'] != id) _latestProfile = null;
      if (id == null) {
        out.add(null);
        return;
      }
      if (_latestProfile == null && !_signingIn) {
        final saved = _cachedProfile(id);
        if (saved != null) {
          _latestProfile = saved;
          out.add(AppUser.fromMap(saved));
        }
      }
      profileSub = _db
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', id)
          .listen((rows) {
            // The row is created by a trigger in the same transaction as the
            // user, so it is normally present on the first event.
            if (rows.isEmpty) return;
            final row = rows.first;
            // A role is never removed, so a role-less row arriving after we
            // already know the role is just a slow, outdated response.
            if (row['role'] == null && _latestProfile?['role'] != null) return;
            _remember(row);
            if (!_signingIn) out.add(AppUser.fromMap(row));
          }, onError: out.addError);
    }

    _flush = () {
      final row = _latestProfile;
      if (row != null && row['id'] == watchingId && !out.isClosed) {
        out.add(AppUser.fromMap(row));
      }
    };

    out = StreamController<AppUser?>(
      onListen: () {
        follow(_auth.currentSession);
        authSub = _auth.onAuthStateChange.listen(
          (s) => follow(s.session),
          onError: out.addError,
        );
      },
      onCancel: () async {
        await authSub?.cancel();
        await profileSub?.cancel();
      },
    );
    return out.stream;
  }

  Future<void> _initGoogle() => _googleReady ??= GoogleSignIn.instance
      .initialize(serverClientId: googleWebClientId);

  @override
  Future<UserRole?> signInWithGoogle(UserRole role) async {
    if (googleWebClientId.isEmpty) {
      throw BackendException(
        'Google sign-in is not set up yet. Add GOOGLE_WEB_CLIENT_ID to .env.',
      );
    }
    await _initGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      throw switch (e.code) {
        GoogleSignInExceptionCode.canceled => SignInCancelled(),
        GoogleSignInExceptionCode.interrupted => BackendException(
          'Sign-in was interrupted. Please try again.',
        ),
        GoogleSignInExceptionCode.uiUnavailable => BackendException(
          'No Google account on this phone. Add one in Settings → Accounts.',
        ),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          BackendException(
            'Google sign-in is not set up for this app build. In Google '
            'Cloud, check the Android OAuth client (package name and SHA-1) '
            'and that GOOGLE_WEB_CLIENT_ID is the Web client ID.',
          ),
        _ => BackendException(
          'Google sign-in failed. ${e.description ?? 'Please try again.'}',
        ),
      };
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw BackendException('Google did not confirm your account. Try again.');
    }
    // One Google tap is all the user does; everything else happens here
    // before the app is told about the account.
    _signingIn = true;
    try {
      final res = await _guard(
        () => _auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        ),
      );
      var row = await _guard(
        () => _db.from('profiles').select().eq('id', res.user!.id).single(),
      );
      final existing = row['role'] as String?;
      if (existing == null) {
        // Brand-new account: give it the role picked on the login screen.
        await _guard(
          () => _db.rpc('complete_profile', params: {'p_role': role.name}),
        );
        row = {...row, 'role': role.name};
      }
      _remember(row);
      if (existing == null) return null;
      return existing == 'collector' ? UserRole.collector : UserRole.household;
    } finally {
      _signingIn = false;
      _flush?.call();
    }
  }

  @override
  Future<void> finishSignUp(UserRole role) async {
    await _guard(
      () => _db.rpc('complete_profile', params: {'p_role': role.name}),
    );
    final row = _latestProfile;
    if (row != null) {
      _remember({...row, 'role': role.name});
      _flush?.call();
    }
  }

  @override
  Future<void> updatePhone(String phone) => _guard(
    () => _db
        .from('profiles')
        .update({'phone': phone.trim()})
        .eq('id', _auth.currentUser!.id),
  );

  @override
  Future<void> updateProfile({String? name, String? phone, String? barangay}) {
    final changes = {
      if (name != null) 'name': name.trim(),
      if (phone != null) 'phone': phone.trim(),
      'barangay': ?barangay,
    };
    if (changes.isEmpty) return Future.value();
    return _guard(
      () =>
          _db.from('profiles').update(changes).eq('id', _auth.currentUser!.id),
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google may not be initialized (e.g. session restored at start-up).
    }
    await cache?.remove(_cacheKey);
    await _auth.signOut();
  }

  @override
  Future<void> setFollowedBarangays(List<String> barangays) => _guard(
    () => _db
        .from('profiles')
        .update({'followed_barangays': barangays})
        .eq('id', _auth.currentUser!.id),
  );
}

// ───────────────────────────── posts ─────────────────────────────

class SupabasePostRepository implements PostRepository {
  static const _bucket = 'post-photos';

  String get _uid =>
      _db.auth.currentUser?.id ??
      (throw BackendException('Please log in again.'));

  List<RecyclablePost> _rows(List<Map<String, dynamic>> rows) =>
      rows.map(RecyclablePost.fromMap).toList();

  @override
  Stream<List<RecyclablePost>> householdPosts(String householdId) => _db
      .from('posts')
      .stream(primaryKey: ['id'])
      .eq('household_id', householdId)
      .order('created_at')
      .map(_rows);

  /// Asks every open [availablePosts] list to reload now.
  final _reloadAvailable = StreamController<void>.broadcast();

  /// Available posts, always from a fresh query.
  ///
  /// Reserved posts are private (only the household and the reserving
  /// collector can read them), so other collectors do not get a realtime
  /// event when a post they can see gets reserved. Realtime is therefore
  /// only a "something changed" signal; the list itself is re-queried on
  /// each signal, every 20 s, and right after a failed reservation.
  @override
  Stream<List<RecyclablePost>> availablePosts() {
    late final StreamController<List<RecyclablePost>> out;
    StreamSubscription<void>? live, reload;
    Timer? poll, debounce;

    Future<void> query() async {
      try {
        final rows = await _db
            .from('posts')
            .select()
            .eq('status', PostStatus.available.name)
            .order('created_at');
        if (!out.isClosed) out.add(_rows(rows));
      } catch (e) {
        if (!out.isClosed) out.addError(e);
      }
    }

    void soon() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 400), query);
    }

    out = StreamController<List<RecyclablePost>>(
      onListen: () {
        query();
        live = _db
            .from('posts')
            .stream(primaryKey: ['id'])
            .eq('status', PostStatus.available.name)
            .listen((_) => soon(), onError: (_) {});
        reload = _reloadAvailable.stream.listen((_) => query());
        poll = Timer.periodic(const Duration(seconds: 20), (_) => query());
      },
      onCancel: () async {
        poll?.cancel();
        debounce?.cancel();
        await reload?.cancel();
        await live?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<List<RecyclablePost>> reservedBy(String collectorId) => _db
      .from('posts')
      .stream(primaryKey: ['id'])
      .eq('reserved_by', collectorId)
      .order('created_at')
      .map(
        (rows) =>
            _rows(rows).where((p) => p.status == PostStatus.reserved).toList(),
      );

  @override
  Stream<RecyclablePost?> watch(String postId) => _db
      .from('posts')
      .stream(primaryKey: ['id'])
      .eq('id', postId)
      .map((rows) => rows.isEmpty ? null : RecyclablePost.fromMap(rows.first));

  /// Uploads to `post-photos/{uid}/{timestamp}.jpg` and returns the public URL.
  Future<String> _upload(String localPath) async {
    final path = '$_uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final bucket = _db.storage.from(_bucket);
    await bucket.upload(
      path,
      File(localPath),
      fileOptions: const FileOptions(contentType: 'image/jpeg'),
    );
    return bucket.getPublicUrl(path);
  }

  /// Best effort: an orphaned photo is harmless, so failures are ignored.
  Future<void> _removePhoto(String url) async {
    final marker = '/$_bucket/';
    final i = url.indexOf(marker);
    if (i < 0) return;
    try {
      await _db.storage.from(_bucket).remove([
        url.substring(i + marker.length),
      ]);
    } catch (_) {}
  }

  @override
  Future<void> create(NewPost post) => _guard(() async {
    if (post.photoPath == null) throw BackendException('Please add a photo.');
    final photoUrl = await _upload(post.photoPath!);
    // household_name / household_phone are filled by a database trigger.
    await _db.from('posts').insert({
      ...post.toColumns(),
      'household_id': _uid,
      'photo_url': photoUrl,
    });
  });

  @override
  Future<void> update(String postId, NewPost post) => _guard(() async {
    final before = await _db
        .from('posts')
        .select('photo_url')
        .eq('id', postId)
        .maybeSingle();
    final newPhoto = post.photoPath == null
        ? null
        : await _upload(post.photoPath!);
    // RLS only lets the owner update while the post is still available.
    final changed = await _db
        .from('posts')
        .update({...post.toColumns(), 'photo_url': ?newPhoto})
        .eq('id', postId)
        .eq('status', PostStatus.available.name)
        .select('id');
    if (changed.isEmpty) {
      if (newPhoto != null) await _removePhoto(newPhoto);
      throw BackendException(
        'A collector already reserved this, so it can no longer be edited.',
      );
    }
    final oldPhoto = before?['photo_url'] as String?;
    if (newPhoto != null && oldPhoto != null) await _removePhoto(oldPhoto);
  });

  @override
  Future<void> delete(String postId) => _guard(() async {
    final removed = await _db
        .from('posts')
        .delete()
        .eq('id', postId)
        .eq('status', PostStatus.available.name)
        .select('photo_url');
    if (removed.isEmpty) {
      throw BackendException(
        'A collector already reserved this. Ask them to cancel first.',
      );
    }
    await _removePhoto(removed.first['photo_url'] as String? ?? '');
  });

  Future<void> _rpc(String fn, Map<String, dynamic> params) =>
      _guard(() => _db.rpc(fn, params: params));

  @override
  Future<void> reserve(String postId) async {
    try {
      await _rpc('reserve_post', {'post_id': postId});
    } catch (_) {
      // Usually "already reserved": drop the stale pin from the map now.
      _reloadAvailable.add(null);
      rethrow;
    }
  }

  @override
  Future<void> cancelReservation(String postId, {String reason = ''}) =>
      _rpc('cancel_reservation', {'post_id': postId, 'reason': reason.trim()});

  @override
  Future<void> markCollected(String postId) =>
      _rpc('mark_collected', {'post_id': postId});

  @override
  Future<void> rateCollector(String postId, int stars) =>
      _rpc('rate_collector', {'post_id': postId, 'stars': stars});

  @override
  /// From the public `collector_ratings` view (averages only), since
  /// households can no longer read a rider's other posts. Views cannot be
  /// streamed, so it refreshes every minute.
  Stream<CollectorRating> collectorRating(String collectorId) async* {
    while (true) {
      try {
        final row = await _db
            .from('collector_ratings')
            .select('average, count')
            .eq('collector_id', collectorId)
            .maybeSingle();
        yield row == null
            ? const CollectorRating(null, 0)
            : CollectorRating(
                (row['average'] as num?)?.toDouble(),
                (row['count'] as num?)?.toInt() ?? 0,
              );
      } catch (_) {
        // Keep the last value; try again next minute.
      }
      await Future<void>.delayed(const Duration(minutes: 1));
    }
  }
}

// ───────────────────────────── routes ─────────────────────────────

class SupabaseRouteRepository implements RouteRepository {
  List<RouteSchedule> _rows(List<Map<String, dynamic>> rows) =>
      rows.map(RouteSchedule.fromMap).where(_isUpcoming).toList();

  @override
  Stream<List<RouteSchedule>> collectorRoutes(String collectorId) => _db
      .from('routes')
      .stream(primaryKey: ['id'])
      .eq('collector_id', collectorId)
      .order('start_time', ascending: true)
      .map(_rows);

  @override
  Stream<List<RouteSchedule>> routesFor(List<String> barangays) {
    if (barangays.isEmpty) return Stream.value(const []);
    return _db
        .from('routes')
        .stream(primaryKey: ['id'])
        .order('start_time', ascending: true)
        .map(
          (rows) =>
              _rows(rows)
                  .where((r) => r.barangays.any(barangays.contains))
                  .toList(),
        );
  }

  @override
  Future<void> schedule({
    required DateTime startTime,
    required List<String> barangays,
    String note = '',
    Map<String, List<String>> puroks = const {},
  }) => _guard(
    // collector_name is filled by a database trigger.
    () => _db.from('routes').insert({
      'collector_id': _db.auth.currentUser!.id,
      'start_time': startTime.toUtc().toIso8601String(),
      'barangays': barangays,
      'note': note.trim(),
      'puroks': {
        for (final e in puroks.entries)
          if (e.value.isNotEmpty && barangays.contains(e.key)) e.key: e.value,
      },
    }),
  );

  @override
  Future<void> delete(String routeId) => _guard(() async {
    // A delete that RLS blocks removes 0 rows without an error; ask for the
    // deleted row back so that case is reported instead of "cancelled".
    final rows = await _db
        .from('routes')
        .delete()
        .eq('id', routeId)
        .select('id');
    if (rows.isEmpty) {
      throw BackendException('Could not cancel this route. Please try again.');
    }
  });
}
