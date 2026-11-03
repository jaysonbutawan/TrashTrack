import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import 'collector_map_tab.dart';
import 'collector_reserved_tab.dart';
import 'collector_routes_tab.dart';

class CollectorHome extends StatefulWidget {
  const CollectorHome({super.key});

  @override
  State<CollectorHome> createState() => _CollectorHomeState();
}

class _CollectorHomeState extends State<CollectorHome> {
  int _tab = 0;
  late final Stream<CollectorRating> _rating = context
      .read<PostRepository>()
      .collectorRating(context.read<AppUser>().id);
  static const _titles = ['Find Recyclables', 'My Reserved', 'My Routes'];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          StreamBuilder<CollectorRating>(
            stream: _rating,
            builder: (context, snap) {
              final avg = snap.data?.average;
              if (avg == null) return const SizedBox.shrink();
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '★ ${avg.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Log out',
            iconSize: 30,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final auth = context.read<AuthRepository>();
              if (await confirm(
                context,
                'Log out?',
                'Are you sure?',
                yes: 'Log Out',
              )) {
                await auth.signOut();
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          CollectorMapTab(user: user),
          CollectorReservedTab(user: user),
          CollectorRoutesTab(user: user),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map, size: 30), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.bookmark, size: 30),
            label: 'Reserved',
          ),
          NavigationDestination(
            icon: Icon(Icons.route, size: 30),
            label: 'Routes',
          ),
        ],
      ),
    );
  }
}
