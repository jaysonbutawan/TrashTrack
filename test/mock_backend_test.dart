import 'package:flutter_test/flutter_test.dart';

import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/constants.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/models/post.dart';

import 'support/mock_backend.dart';

void main() {
  late MockStore store;
  late MockAuthRepository auth;
  late MockPostRepository posts;

  setUp(() {
    store = MockStore();
    auth = MockAuthRepository(store);
    posts = MockPostRepository(store);
  });

  Future<RecyclablePost> post(String id) =>
      posts.watch(id).first.then((p) => p!);

  test('available -> reserved -> collected -> rated', () async {
    auth.signInAs(UserRole.collector);
    await posts.reserve('p1');
    expect((await post('p1')).status, PostStatus.reserved);

    // A second reservation is refused.
    expect(() => posts.reserve('p1'), throwsA(isA<BackendException>()));

    await posts.markCollected('p1');
    expect((await post('p1')).status, PostStatus.collected);

    await auth.signOut();
    auth.signInAs(UserRole.household);
    await posts.rateCollector('p1', 5);
    expect((await post('p1')).rating, 5);
    expect(
      () => posts.rateCollector('p1', 4),
      throwsA(isA<BackendException>()),
    );
  });

  test('cancel puts the post back to available', () async {
    auth.signInAs(UserRole.collector);
    await posts.reserve('p4');
    await posts.cancelReservation('p4');
    final p = await post('p4');
    expect(p.status, PostStatus.available);
    expect(p.reservedBy, isNull);
  });

  test('household cannot delete a reserved post', () async {
    auth.signInAs(UserRole.household);
    expect(() => posts.delete('p2'), throwsA(isA<BackendException>()));
  });

  test('household edits an available post, not a reserved one', () async {
    auth.signInAs(UserRole.household);
    final p1 = await post('p1');
    final edit = NewPost(
      types: [RecyclableType.glass],
      weightKg: 12.5,
      location: p1.location,
      barangay: 'Apokon',
      label: PostLabel.forSale,
      notes: 'Updated',
    );
    await posts.update('p1', edit);
    final after = await post('p1');
    expect(after.weightKg, 12.5);
    expect(after.types, [RecyclableType.glass]);
    expect(after.barangay, 'Apokon');
    expect(after.photoUrl, p1.photoUrl); // no new photo → keep the old one

    expect(() => posts.update('p2', edit), throwsA(isA<BackendException>()));
  });

  test('new Google account is ready with the role picked on login', () async {
    final existing = await auth.signInWithGoogle(UserRole.collector);
    expect(existing, isNull);
    final me = await auth.currentUser().first;
    expect(me!.needsProfile, isFalse);
    expect(me.isCollector, isTrue);
    expect(
      () => auth.finishSignUp(UserRole.household),
      throwsA(isA<BackendException>()),
    );
  });

  test('interrupted sign-up can be finished afterwards', () async {
    auth.interruptSignUp = true;
    await auth.signInWithGoogle(UserRole.collector);
    expect((await auth.currentUser().first)!.needsProfile, isTrue);
    await auth.finishSignUp(UserRole.household);
    final me = await auth.currentUser().first;
    expect(me!.needsProfile, isFalse);
    expect(me.isCollector, isFalse);
  });

  test('existing Google account keeps its role', () async {
    auth.nextGoogleAccount = 'u-household-1';
    final existing = await auth.signInWithGoogle(UserRole.collector);
    expect(existing, UserRole.household);
  });

  test('formatKg', () {
    expect(formatKg(12), '12 kg');
    expect(formatKg(2.5), '2.5 kg');
  });
}
