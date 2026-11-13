import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../data/repositories.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/post_detail_screen.dart';
import 'route_guide_screen.dart';

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
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _RouteGuideBanner(pickups: list);
            final p = list[i - 1];
            return PostCard(
              post: p,
              showStatus: false, // everything on this tab is reserved
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

/// Opens the shortest route through all reserved pickups.
class _RouteGuideBanner extends StatelessWidget {
  const _RouteGuideBanner({required this.pickups});
  final List<RecyclablePost> pickups;

  @override
  Widget build(BuildContext context) {
    final n = pickups.length;
    final kg = pickups.fold(0.0, (a, p) => a + p.weightKg);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: Brand.forest,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final user = context.read<AppUser>();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Provider.value(
                  value: user,
                  child: const RouteGuideScreen(),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.route, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Route Guide',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Shortest way to your $n pickup${n == 1 ? '' : 's'} '
                        '· ${formatKg(kg)}',
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
