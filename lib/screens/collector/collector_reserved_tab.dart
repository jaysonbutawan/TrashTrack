import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import '../common/post_detail_screen.dart';

class CollectorReservedTab extends StatefulWidget {
  const CollectorReservedTab({super.key, required this.user});
  final AppUser user;

  @override
  State<CollectorReservedTab> createState() => _CollectorReservedTabState();
}

class _CollectorReservedTabState extends State<CollectorReservedTab> {
  late final Stream<List<RecyclablePost>> _posts = context
      .read<PostRepository>()
      .reservedBy(widget.user.id);

  @override
  Widget build(BuildContext context) {
    final service = context.read<PostRepository>();
    return StreamBuilder<List<RecyclablePost>>(
      stream: _posts,
      builder: (context, snap) {
        if (snap.hasError) {
          return const EmptyMessage(Icons.wifi_off, 'Could not load.');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyMessage(
            Icons.bookmark_border,
            'Nothing reserved.\nGo to the Map to find recyclables.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final p = list[i];
            return PostCard(
              post: p,
              onTap: () => openPostDetail(context, p.id),
              trailing: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                onPressed: () async {
                  if (await confirm(
                        context,
                        'Mark as collected?',
                        'Did you already pick up these recyclables?',
                      ) &&
                      context.mounted) {
                    await runWithFeedback(
                      context,
                      () => service.markCollected(p.id),
                      successMessage: 'Marked as collected.',
                    );
                  }
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Collected'),
              ),
            );
          },
        );
      },
    );
  }
}
