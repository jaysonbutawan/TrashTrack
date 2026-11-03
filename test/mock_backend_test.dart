import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/mock/mock_backend.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/models/post.dart';

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
    await auth.signIn(email: 'collector@demo.ph', password: 'demo123');
    await posts.reserve('p1');
    expect((await post('p1')).status, PostStatus.reserved);

    // A second reservation is refused.
    expect(() => posts.reserve('p1'), throwsA(isA<BackendException>()));

    await posts.markCollected('p1');
    expect((await post('p1')).status, PostStatus.collected);

    await auth.signOut();
    await auth.signIn(email: 'household@demo.ph', password: 'demo123');
    await posts.rateCollector('p1', 5);
    expect((await post('p1')).rating, 5);
    expect(
      () => posts.rateCollector('p1', 4),
      throwsA(isA<BackendException>()),
    );
  });

  test('cancel puts the post back to available', () async {
    await auth.signIn(email: 'collector@demo.ph', password: 'demo123');
    await posts.reserve('p4');
    await posts.cancelReservation('p4');
    final p = await post('p4');
    expect(p.status, PostStatus.available);
    expect(p.reservedBy, isNull);
  });

  test('household cannot delete a reserved post', () async {
    await auth.signIn(email: 'household@demo.ph', password: 'demo123');
    expect(() => posts.delete('p2'), throwsA(isA<BackendException>()));
  });

  test('wrong password is refused', () {
    expect(
      () => auth.signIn(email: 'household@demo.ph', password: 'x'),
      throwsA(isA<BackendException>()),
    );
  });
}
