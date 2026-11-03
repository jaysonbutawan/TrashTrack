import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../models/route_schedule.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/post_service.dart';
import '../../services/route_service.dart';
import '../../widgets/common.dart';
import '../common/post_detail_screen.dart';
import 'create_post_screen.dart';
import 'follow_barangays_screen.dart';

class HouseholdHome extends StatefulWidget {
  const HouseholdHome({super.key});

  @override
  State<HouseholdHome> createState() => _HouseholdHomeState();
}

class _HouseholdHomeState extends State<HouseholdHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Make sure this device receives alerts for the barangays the user follows.
    final user = context.read<AppUser>();
    final n = context.read<NotificationService>();
    n.requestPermission().then((_) => n.syncBarangayTopics(
        previous: const [], now: user.followedBarangays));
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'Log out?', 'You will stop getting route alerts on this phone.',
        yes: 'Log Out')) {
      return;
    }
    if (!mounted) return;
    final user = context.read<AppUser>();
    await context.read<NotificationService>().unsubscribeAll(user.followedBarangays);
    if (mounted) await context.read<AuthService>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'My Recyclables' : 'Collector Routes'),
        actions: [
          IconButton(
              tooltip: 'Log out',
              iconSize: 30,
              onPressed: _logout,
              icon: const Icon(Icons.logout)),
        ],
      ),
      body: _tab == 0 ? _MyPosts(user: user) : _Routes(user: user),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => Provider.value(
                      value: user, child: const CreatePostScreen()))),
              icon: const Icon(Icons.add_a_photo, size: 28),
              label: const Text('Post Recyclables',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.inventory_2, size: 30), label: 'My Posts'),
          NavigationDestination(
              icon: Icon(Icons.local_shipping, size: 30), label: 'Routes'),
        ],
      ),
    );
  }
}

class _MyPosts extends StatelessWidget {
  const _MyPosts({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final posts = context.read<PostService>();
    return StreamBuilder<List<RecyclablePost>>(
      stream: posts.householdPosts(user.uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return const EmptyMessage(Icons.wifi_off, 'Could not load your posts.');
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyMessage(Icons.recycling,
              'No posts yet.\nTap "Post Recyclables" to add one.');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final p = list[i];
            Widget? trailing;
            if (p.status == PostStatus.reserved) {
              trailing = Text('Reserved by ${p.reservedByName ?? 'a collector'}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
            } else if (p.status == PostStatus.collected && p.rating == null) {
              trailing = FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.amber.shade800),
                onPressed: () => rateCollectorFlow(context, p),
                icon: const Icon(Icons.star),
                label: const Text('Rate Collector'),
              );
            } else if (p.rating != null) {
              trailing = Text('You rated: ${'★' * p.rating!}',
                  style: TextStyle(fontSize: 17, color: Colors.amber.shade800));
            }
            return PostCard(
              post: p,
              trailing: trailing,
              onTap: () => openPostDetail(context, p.id),
            );
          },
        );
      },
    );
  }
}

class _Routes extends StatelessWidget {
  const _Routes({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final routes = context.read<RouteService>();
    final followed = user.followedBarangays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                followed.isEmpty
                    ? 'Follow your barangay to get alerts when a collector is coming.'
                    : 'Following: ${followed.join(', ')}',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => Provider.value(
                            value: user, child: const FollowBarangaysScreen()))),
                icon: const Icon(Icons.notifications_active),
                label: Text(followed.isEmpty ? 'Follow My Barangay' : 'Change Barangays'),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<List<RouteSchedule>>(
            stream: routes.routesFor(followed),
            builder: (context, snap) {
              if (snap.hasError) {
                return const EmptyMessage(Icons.wifi_off, 'Could not load routes.');
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return EmptyMessage(
                    Icons.event_busy,
                    followed.isEmpty
                        ? 'No barangay followed yet.'
                        : 'No collector routes scheduled yet.');
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => RouteTile(route: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RouteTile extends StatelessWidget {
  const RouteTile({super.key, required this.route, this.onDelete});
  final RouteSchedule route;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('EEE, MMM d • h:mm a').format(route.startTime);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.local_shipping, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(when,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(route.barangays.join(', '),
                      style: const TextStyle(fontSize: 17)),
                  if (onDelete == null)
                    Text('Collector: ${route.collectorName}',
                        style: const TextStyle(fontSize: 16, color: Colors.black54)),
                  if (route.note.isNotEmpty)
                    Text(route.note,
                        style: const TextStyle(
                            fontSize: 16, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                  iconSize: 30,
                  tooltip: 'Cancel route',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ),
      ),
    );
  }
}
