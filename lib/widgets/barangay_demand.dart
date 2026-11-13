import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/post.dart';
import '../route_planner.dart';
import '../theme.dart';

/// "5 posts · 32 kg".
String demandSummary(BarangayDemand d) =>
    '${d.posts} post${d.posts == 1 ? '' : 's'} · ${formatKg(d.totalKg)}';

/// One barangay in the "busiest barangays" ranking.
class DemandTile extends StatelessWidget {
  const DemandTile({
    super.key,
    required this.rank,
    required this.demand,
    required this.maxPosts,
    this.onTap,
    this.actionIcon = Icons.chevron_right,
  });

  final int rank;
  final BarangayDemand demand;

  /// Posts in the busiest barangay, for the size of the bar.
  final int maxPosts;
  final VoidCallback? onTap;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final d = demand;
    final top = rank == 1;
    final next = d.nextRoute;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: top ? Brand.kraft : Brand.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: top
                    ? const Icon(
                        Icons.local_fire_department,
                        color: Colors.white,
                      )
                    : Text(
                        '$rank',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Brand.forest,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.barangay,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Brand.ink,
                      ),
                    ),
                    Text(
                      '${demandSummary(d)}'
                      '${d.forSale > 0 ? ' · ${d.forSale} for sale' : ''}'
                      '${d.free > 0 ? ' · ${d.free} free' : ''}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Brand.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxPosts == 0 ? 0 : d.posts / maxPosts,
                        minHeight: 6,
                        color: top ? Brand.kraft : Brand.leaf,
                        backgroundColor: Brand.line,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          next == null ? Icons.campaign : Icons.event_available,
                          size: 16,
                          color: next == null ? Brand.kraft : Brand.inkSoft,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            next == null
                                ? 'No collector scheduled yet'
                                : '${next.collectorName} goes '
                                      '${DateFormat('EEE, MMM d').format(next.startTime)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: next == null
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: next == null ? Brand.kraft : Brand.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(actionIcon, color: Brand.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing every barangay with available posts, busiest first.
/// Returns the one the collector tapped.
Future<BarangayDemand?> showBusyBarangays(
  BuildContext context,
  List<BarangayDemand> ranking,
) {
  return showModalBottomSheet<BarangayDemand>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 2),
            child: Text(
              'Where the recyclables are',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Barangays with the most posts waiting right now. '
              'Tap one to see it on the map.',
              style: TextStyle(fontSize: 15, color: Brand.inkSoft),
            ),
          ),
          if (ranking.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No posts are waiting right now.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, color: Brand.inkSoft),
              ),
            ),
          for (var i = 0; i < ranking.length; i++)
            DemandTile(
              rank: i + 1,
              demand: ranking[i],
              maxPosts: ranking.first.posts,
              actionIcon: Icons.map,
              onTap: () => Navigator.pop(ctx, ranking[i]),
            ),
        ],
      ),
    ),
  );
}
