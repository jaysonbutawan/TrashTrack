import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../services/post_service.dart';
import '../../widgets/common.dart';
import '../../widgets/tagum_map.dart';

void openPostDetail(BuildContext context, String postId) {
  final user = context.read<AppUser>();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          Provider.value(value: user, child: PostDetailScreen(postId: postId)),
    ),
  );
}

Future<void> rateCollectorFlow(BuildContext context, RecyclablePost post) async {
  final stars = await askForRating(context, post.reservedByName ?? 'collector');
  if (stars == null || !context.mounted) return;
  await runWithFeedback(
    context,
    () => context.read<PostService>().rateCollector(post, stars),
    successMessage: 'Thank you for rating!',
  );
}

Future<void> _call(BuildContext context, String phone) async {
  final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
  if (!ok && context.mounted) {
    showMessage(ScaffoldMessenger.of(context), 'Cannot open the phone app.',
        error: true);
  }
}

Future<void> _directions(RecyclablePost p) => launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination='
          '${p.location.latitude},${p.location.longitude}'),
      mode: LaunchMode.externalApplication,
    );

class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RecyclablePost?>(
      stream: context.read<PostService>().watch(postId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()));
        }
        final post = snap.data;
        if (post == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const EmptyMessage(
                  Icons.delete_outline, 'This post was removed.'));
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Recyclables')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Image.network(post.photoUrl,
                  height: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                      height: 200,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.image, size: 64))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      StatusPill(post.status),
                      LabelPill(post.label),
                    ]),
                    const SizedBox(height: 12),
                    Text(post.typesLabel,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _Info(Icons.scale, 'Amount', post.amount),
                    _Info(Icons.place, 'Barangay', post.barangay),
                    _Info(Icons.person, 'Household', post.householdName),
                    if (post.notes.isNotEmpty)
                      _Info(Icons.notes, 'Notes', post.notes),
                    if (post.label == PostLabel.forSale)
                      const _Info(Icons.handshake, 'Price',
                          'Agreed in person at pickup'),
                    if (post.reservedByName != null)
                      _CollectorInfo(post: post),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: TagumMap(
                          initialCenter: post.location,
                          initialZoom: 16,
                          markers: [
                            Marker(
                              point: post.location,
                              width: 50,
                              height: 50,
                              alignment: Alignment.topCenter,
                              child: const Icon(Icons.location_pin,
                                  size: 50, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Actions(post: post),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 26, color: Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: value),
              ]),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ]),
      );
}

/// Collector name with their average rating (shown to households).
class _CollectorInfo extends StatelessWidget {
  const _CollectorInfo({required this.post});
  final RecyclablePost post;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: context.read<AuthService>().profile(post.reservedBy!),
      builder: (context, snap) {
        final c = snap.data;
        final avg = c?.averageRating;
        final rating = avg == null
            ? 'no ratings yet'
            : '★ ${avg.toStringAsFixed(1)} (${c!.ratingCount})';
        return _Info(Icons.local_shipping, 'Collector',
            '${post.reservedByName} • $rating');
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.post});
  final RecyclablePost post;

  @override
  Widget build(BuildContext context) {
    final user = context.read<AppUser>();
    final posts = context.read<PostService>();
    final mine = post.reservedBy == user.uid;
    final children = <Widget>[];

    if (user.isCollector) {
      switch (post.status) {
        case PostStatus.available:
          children.add(FilledButton.icon(
            onPressed: () => runWithFeedback(
                context, () => posts.reserve(post.id, user),
                successMessage: 'Reserved! Others can no longer take it.'),
            icon: const Icon(Icons.bookmark_add),
            label: const Text('Reserve'),
          ));
        case PostStatus.reserved when mine:
          children.addAll([
            FilledButton.icon(
              onPressed: () async {
                if (await confirm(context, 'Mark as collected?',
                        'Did you already pick up these recyclables?') &&
                    context.mounted) {
                  await runWithFeedback(
                      context, () => posts.markCollected(post.id, user.uid),
                      successMessage: 'Marked as collected.');
                }
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Mark Collected'),
            ),
            OutlinedButton.icon(
              onPressed: () => _call(context, post.householdPhone),
              icon: const Icon(Icons.call),
              label: const Text('Call Household'),
            ),
            OutlinedButton.icon(
              onPressed: () => _directions(post),
              icon: const Icon(Icons.directions),
              label: const Text('Directions'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  foregroundColor: Colors.red.shade700,
                  textStyle: const TextStyle(fontSize: 18)),
              onPressed: () async {
                if (await confirm(context, 'Cancel reservation?',
                        'Other collectors will be able to reserve it again.') &&
                    context.mounted) {
                  await runWithFeedback(context,
                      () => posts.cancelReservation(post.id, user.uid),
                      successMessage: 'Reservation cancelled.');
                }
              },
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel Reservation'),
            ),
          ]);
        case PostStatus.reserved:
          children.add(const Text('Another collector reserved this.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18)));
        case PostStatus.collected:
          children.add(Text(
              mine ? 'You collected this. Salamat!' : 'Already collected.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18)));
      }
    } else if (post.householdId == user.uid) {
      switch (post.status) {
        case PostStatus.available:
          children.add(OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade700, width: 2)),
            onPressed: () async {
              if (await confirm(context, 'Delete this post?',
                      'Collectors will no longer see it.',
                      yes: 'Delete') &&
                  context.mounted) {
                final nav = Navigator.of(context);
                if (await runWithFeedback(context, () => posts.delete(post),
                    successMessage: 'Post deleted.')) {
                  nav.pop();
                }
              }
            },
            icon: const Icon(Icons.delete),
            label: const Text('Delete Post'),
          ));
        case PostStatus.reserved:
          children.add(const Text(
              'A collector is coming. Agree on the price when they arrive.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18)));
        case PostStatus.collected:
          if (post.rating == null) {
            children.add(FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade800),
              onPressed: () => rateCollectorFlow(context, post),
              icon: const Icon(Icons.star),
              label: const Text('Rate Collector'),
            ));
          } else {
            children.add(Text('You rated: ${'★' * post.rating!}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, color: Colors.amber.shade800)));
          }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in children)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
      ],
    );
  }
}
