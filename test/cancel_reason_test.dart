import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/models/post.dart';

import 'support/mock_backend.dart';

void main() {
  test('cancel reason is saved and the post is available again', () async {
    final store = MockStore();
    MockAuthRepository(store).signInAs(UserRole.collector);
    final posts = MockPostRepository(store);
    final mine = store.posts.firstWhere(
      (p) =>
          p.status == PostStatus.reserved &&
          p.reservedBy == store.currentUser!.id,
    );

    await posts.cancelReservation(mine.id, reason: ' Price not agreed ');

    final after = store.posts.firstWhere((p) => p.id == mine.id);
    expect(after.status, PostStatus.available);
    expect(after.reservedBy, isNull);
    expect(after.cancelReason, 'Price not agreed');
  });

  test('cancel_reason column is read from the database row', () {
    final p = RecyclablePost.fromMap({
      'id': 'p1',
      'household_id': 'h1',
      'lat': 7.44,
      'lng': 125.8,
      'created_at': '2026-11-16T00:00:00Z',
      'cancel_reason': 'Not collected – no one was home',
    });
    expect(p.cancelReason, 'Not collected – no one was home');
  });
}
