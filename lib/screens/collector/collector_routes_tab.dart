import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../models/route_schedule.dart';
import '../../route_planner.dart';
import '../../theme.dart';
import '../../widgets/barangay_demand.dart';
import '../../widgets/common.dart';
import '../../widgets/route_tile.dart';
import 'schedule_route_screen.dart';

class CollectorRoutesTab extends StatefulWidget {
  const CollectorRoutesTab({super.key, required this.user});
  final AppUser user;

  @override
  State<CollectorRoutesTab> createState() => _CollectorRoutesTabState();
}

class _CollectorRoutesTabState extends State<CollectorRoutesTab> {
  late final Stream<List<RouteSchedule>> _mine = context
      .read<RouteRepository>()
      .collectorRoutes(widget.user.id);
  late final Stream<List<RouteSchedule>> _everyone = context
      .read<RouteRepository>()
      .routesFor(tagumBarangays);
  late final Stream<List<RecyclablePost>> _available = context
      .read<PostRepository>()
      .availablePosts();

  void _schedule([List<String> barangays = const []]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Provider.value(
          value: widget.user,
          child: ScheduleRouteScreen(initialBarangays: barangays),
        ),
      ),
    );
  }

  Future<void> _cancel(RouteSchedule r) async {
    final service = context.read<RouteRepository>();
    if (await confirm(
          context,
          'Cancel this route?',
          'It will be removed from the households\' list.',
          danger: true,
        ) &&
        mounted) {
      await runWithFeedback(
        context,
        () => service.delete(r.id),
        successMessage: 'Route cancelled.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RouteSchedule>>(
      stream: _mine,
      builder: (context, snap) {
        final mine = snap.data ?? const <RouteSchedule>[];
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FilledButton.icon(
                onPressed: _schedule,
                icon: const Icon(Icons.add_road),
                label: const Text('Schedule a Route'),
              ),
            ),
            _Suggestions(
              available: _available,
              everyone: _everyone,
              onSchedule: _schedule,
            ),
            const _Heading('Your upcoming routes'),
            if (snap.hasError)
              const _Note(Icons.wifi_off, 'Could not load your routes.')
            else if (!snap.hasData)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (mine.isEmpty)
              const _Note(
                Icons.route,
                'No upcoming routes. Schedule one so households know you '
                'are coming.',
              )
            else
              for (final r in mine)
                RouteTile(route: r, onDelete: () => _cancel(r)),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 13.5,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: Brand.inkSoft,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Row(
      children: [
        Icon(icon, color: Brand.inkSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, color: Brand.inkSoft),
          ),
        ),
      ],
    ),
  );
}

/// "Where should I go next?" — busy barangays, favouring the ones no
/// collector has scheduled yet (see [suggestBarangays]).
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.available,
    required this.everyone,
    required this.onSchedule,
  });

  final Stream<List<RecyclablePost>> available;
  final Stream<List<RouteSchedule>> everyone;
  final void Function(List<String> barangays) onSchedule;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RecyclablePost>>(
      stream: available,
      builder: (context, posts) => StreamBuilder<List<RouteSchedule>>(
        stream: everyone,
        builder: (context, routes) {
          final ranking = rankBarangays(
            posts.data ?? const [],
            routes.data ?? const [],
          );
          if (ranking.isEmpty) return const SizedBox.shrink();
          final picks = suggestBarangays(ranking);
          final names = [for (final d in picks) d.barangay];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading('Suggested for your next route'),
              for (var i = 0; i < picks.length; i++)
                DemandTile(
                  rank: i + 1,
                  hot: picks[i] == ranking.first,
                  demand: picks[i],
                  maxPosts: ranking.first.posts,
                  actionIcon: Icons.add_circle_outline,
                  onTap: () => onSchedule([picks[i].barangay]),
                ),
              if (picks.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Brand.card,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => onSchedule(names),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text('Plan a Route for These ${picks.length}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
