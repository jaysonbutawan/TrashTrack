// TEST ONLY: in-memory implementation of the backend endpoints, seeded with
// static data. The app itself always uses Supabase.

import 'dart:async';

import 'package:hitchmeup/constants.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/models/post.dart';
import 'package:hitchmeup/models/route_schedule.dart';
import 'package:hitchmeup/data/repositories.dart';

import 'mock_data.dart';

const _latency = Duration(milliseconds: 400);

/// Shared state behind all mock repositories.
class MockStore {
  final Map<String, AppUser> accounts = {
    for (final u in mockAccounts.values) u.id: u,
  };
  final List<RecyclablePost> posts = buildMockPosts();
  final List<RouteSchedule> routes = buildMockRoutes();
  AppUser? currentUser;

  final _changes = StreamController<void>.broadcast();
  int _nextId = 1000;

  String newId(String prefix) => '$prefix${_nextId++}';
  void notify() => _changes.add(null);

  /// Emits the current value now and again after every change.
  Stream<T> watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  AppUser requireUser() =>
      currentUser ?? (throw BackendException('Please log in again.'));

  int indexOfPost(String id) {
    final i = posts.indexWhere((p) => p.id == id);
    if (i < 0) throw BackendException('This post was removed.');
    return i;
  }
}

class MockAuthRepository extends AuthRepository {
  MockAuthRepository(this._s);
  final MockStore _s;

  /// Who "Google" signs in as next: a sample user's id, or null for a
  /// brand-new account.
  String? nextGoogleAccount;

  /// Test switch: the role is NOT saved during sign-in (as when the
  /// connection drops half-way), leaving an account that needs [finishSignUp].
  bool interruptSignUp = false;

  @override
  Stream<AppUser?> currentUser() => _s.watch(() => _s.currentUser);

  void _setUser(AppUser user) {
    _s.accounts[user.id] = user;
    _s.currentUser = user;
    _s.notify();
  }

  /// Test helper: sign in directly as a sample user.
  void signInAs(UserRole role) =>
      _setUser(_s.accounts[mockAccounts[role]!.id]!);

  @override
  Future<UserRole?> signInWithGoogle(UserRole role) async {
    await Future<void>.delayed(_latency);
    final existing = nextGoogleAccount == null
        ? null
        : _s.accounts[nextGoogleAccount];
    if (existing != null) {
      _setUser(existing);
      return existing.role;
    }
    _setUser(
      AppUser(
        id: _s.newId('u-'),
        name: 'Juan Dela Paz',
        phone: '',
        role: role,
        email: 'juan.delapaz@gmail.com',
        needsProfile: interruptSignUp,
      ),
    );
    return null;
  }

  @override
  Future<void> finishSignUp(UserRole role) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    if (!user.needsProfile) {
      throw BackendException('Your account is already set up.');
    }
    _setUser(user.copyWith(role: role, needsProfile: false));
  }

  @override
  Future<void> updatePhone(String phone) async {
    await Future<void>.delayed(_latency);
    _setUser(_s.requireUser().copyWith(phone: phone.trim()));
  }

  @override
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? barangay,
  }) async {
    await Future<void>.delayed(_latency);
    if (name != null && name.trim().isEmpty) {
      throw BackendException('Please enter your name.');
    }
    _setUser(
      _s.requireUser().copyWith(
        name: name?.trim(),
        phone: phone?.trim(),
        barangay: barangay,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _s.currentUser = null;
    _s.notify();
  }

  @override
  Future<void> setFollowedBarangays(List<String> barangays) async {
    await Future<void>.delayed(_latency);
    _setUser(_s.requireUser().copyWith(followedBarangays: barangays));
  }
}

class MockPostRepository implements PostRepository {
  MockPostRepository(this._s);
  final MockStore _s;

  @override
  Stream<List<RecyclablePost>> householdPosts(String householdId) => _s.watch(
    () => _s.posts.where((p) => p.householdId == householdId).toList(),
  );

  @override
  Stream<List<RecyclablePost>> availablePosts() => _s.watch(
    () => _s.posts.where((p) => p.status == PostStatus.available).toList(),
  );

  @override
  Stream<List<RecyclablePost>> reservedBy(String collectorId) => _s.watch(
    () => _s.posts
        .where(
          (p) => p.status == PostStatus.reserved && p.reservedBy == collectorId,
        )
        .toList(),
  );

  @override
  Stream<RecyclablePost?> watch(String postId) => _s.watch(() {
    final i = _s.posts.indexWhere((p) => p.id == postId);
    return i < 0 ? null : _s.posts[i];
  });

  void _check(NewPost input) {
    if (!isInsideTagum(input.location)) {
      throw BackendException('The pin must be inside Tagum City.');
    }
    if (input.types.isEmpty) {
      throw BackendException('Choose at least one type.');
    }
    if (input.weightKg <= 0) throw BackendException('Enter the weight.');
  }

  @override
  Future<void> create(NewPost input) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    _check(input);
    _s.posts.insert(
      0,
      RecyclablePost(
        id: _s.newId('p'),
        householdId: user.id,
        householdName: user.name,
        householdPhone: user.phone,
        // A real backend returns the uploaded URL; the mock keeps the local path.
        photoUrl: input.photoPath ?? '',
        types: input.types,
        weightKg: input.weightKg,
        location: input.location,
        barangay: input.barangay,
        label: input.label,
        status: PostStatus.available,
        notes: input.notes.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _s.notify();
  }

  @override
  Future<void> update(String postId, NewPost input) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    _check(input);
    final i = _s.indexOfPost(postId);
    final p = _s.posts[i];
    if (p.householdId != user.id) {
      throw BackendException('You can only edit your own posts.');
    }
    if (p.status != PostStatus.available) {
      throw BackendException(
        'A collector already reserved this, so it can no longer be edited.',
      );
    }
    _s.posts[i] = p.copyWith(
      photoUrl: input.photoPath,
      types: input.types,
      weightKg: input.weightKg,
      location: input.location,
      barangay: input.barangay,
      label: input.label,
      notes: input.notes.trim(),
    );
    _s.notify();
  }

  @override
  Future<void> delete(String postId) async {
    await Future<void>.delayed(_latency);
    final p = _s.posts[_s.indexOfPost(postId)];
    if (p.status != PostStatus.available) {
      throw BackendException(
        'A collector already reserved this. Ask them to cancel first.',
      );
    }
    _s.posts.removeWhere((x) => x.id == postId);
    _s.notify();
  }

  @override
  Future<void> reserve(String postId) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    final i = _s.indexOfPost(postId);
    if (_s.posts[i].status != PostStatus.available) {
      throw BackendException('Sorry, another collector already reserved this.');
    }
    _s.posts[i] = _s.posts[i].copyWith(
      status: PostStatus.reserved,
      reservedBy: () => user.id,
      reservedByName: () => user.name,
      reservedAt: () => DateTime.now(),
    );
    _s.notify();
  }

  @override
  Future<void> cancelReservation(String postId) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    final i = _s.indexOfPost(postId);
    final p = _s.posts[i];
    if (p.status != PostStatus.reserved || p.reservedBy != user.id) {
      throw BackendException('You can no longer cancel this.');
    }
    _s.posts[i] = p.copyWith(
      status: PostStatus.available,
      reservedBy: () => null,
      reservedByName: () => null,
      reservedAt: () => null,
    );
    _s.notify();
  }

  @override
  Future<void> markCollected(String postId) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    final i = _s.indexOfPost(postId);
    final p = _s.posts[i];
    if (p.status != PostStatus.reserved || p.reservedBy != user.id) {
      throw BackendException(
        'Only the collector who reserved this can mark it collected.',
      );
    }
    _s.posts[i] = p.copyWith(
      status: PostStatus.collected,
      collectedAt: () => DateTime.now(),
    );
    _s.notify();
  }

  @override
  Future<void> rateCollector(String postId, int stars) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    final i = _s.indexOfPost(postId);
    final p = _s.posts[i];
    if (p.householdId != user.id || p.status != PostStatus.collected) {
      throw BackendException('You can rate only after pickup.');
    }
    if (p.rating != null) {
      throw BackendException('You already rated this pickup.');
    }
    _s.posts[i] = p.copyWith(rating: () => stars.clamp(1, 5));
    _s.notify();
  }

  @override
  Stream<CollectorRating> collectorRating(String collectorId) => _s.watch(
    () => CollectorRating.fromStars([
      ...?mockPastRatings[collectorId],
      ..._s.posts
          .where((p) => p.reservedBy == collectorId)
          .map((p) => p.rating)
          .whereType<int>(),
    ]),
  );
}

class MockRouteRepository implements RouteRepository {
  MockRouteRepository(this._s);
  final MockStore _s;

  List<RouteSchedule> _upcoming(bool Function(RouteSchedule) test) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return _s.routes
        .where((r) => !r.startTime.isBefore(startOfToday) && test(r))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  @override
  Stream<List<RouteSchedule>> collectorRoutes(String collectorId) =>
      _s.watch(() => _upcoming((r) => r.collectorId == collectorId));

  @override
  Stream<List<RouteSchedule>> routesFor(List<String> barangays) =>
      _s.watch(() => _upcoming((r) => r.barangays.any(barangays.contains)));

  @override
  Future<void> schedule({
    required DateTime startTime,
    required List<String> barangays,
    String note = '',
  }) async {
    await Future<void>.delayed(_latency);
    final user = _s.requireUser();
    _s.routes.add(
      RouteSchedule(
        id: _s.newId('r'),
        collectorId: user.id,
        collectorName: user.name,
        startTime: startTime,
        barangays: barangays,
        note: note.trim(),
      ),
    );
    _s.notify();
  }

  @override
  Future<void> delete(String routeId) async {
    await Future<void>.delayed(_latency);
    _s.routes.removeWhere((r) => r.id == routeId);
    _s.notify();
  }
}
