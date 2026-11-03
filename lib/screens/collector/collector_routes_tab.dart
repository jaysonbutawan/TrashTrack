import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/route_schedule.dart';
import '../../services/route_service.dart';
import '../../widgets/common.dart';
import '../household/household_home.dart' show RouteTile;
import 'schedule_route_screen.dart';

class CollectorRoutesTab extends StatefulWidget {
  const CollectorRoutesTab({super.key, required this.user});
  final AppUser user;

  @override
  State<CollectorRoutesTab> createState() => _CollectorRoutesTabState();
}

class _CollectorRoutesTabState extends State<CollectorRoutesTab> {
  late final Stream<List<RouteSchedule>> _routes =
      context.read<RouteService>().collectorRoutes(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    final service = context.read<RouteService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => Provider.value(
                      value: widget.user, child: const ScheduleRouteScreen())),
            ),
            icon: const Icon(Icons.add_road),
            label: const Text('Schedule a Route'),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<RouteSchedule>>(
            stream: _routes,
            builder: (context, snap) {
              if (snap.hasError) {
                return const EmptyMessage(Icons.wifi_off, 'Could not load.');
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return const EmptyMessage(Icons.route,
                    'No upcoming routes.\nSchedule one so households know you are coming.');
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final r = list[i];
                  return RouteTile(
                    route: r,
                    onDelete: () async {
                      if (await confirm(context, 'Cancel this route?',
                              'It will be removed from the households\' list.') &&
                          context.mounted) {
                        await runWithFeedback(
                            context, () => service.delete(r.id),
                            successMessage: 'Route cancelled.');
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
