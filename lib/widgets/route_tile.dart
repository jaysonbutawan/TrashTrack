import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/route_schedule.dart';
import '../theme.dart';

/// A scheduled collector visit: calendar block + time + barangays.
/// Pass [onDelete] for the collector's own routes.
class RouteTile extends StatelessWidget {
  const RouteTile({
    super.key,
    required this.route,
    this.onDelete,
    this.highlight = const [],
  });

  final RouteSchedule route;
  final VoidCallback? onDelete;

  /// Barangays to emphasise (the ones the household follows).
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final t = route.startTime;
    final now = DateTime.now();
    final days = DateTime(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final when = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => DateFormat('EEEE').format(t),
    };
    final soon = days <= 1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 66,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: soon ? Brand.forest : Brand.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM').format(t).toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: soon ? Colors.white70 : Brand.forest,
                    ),
                  ),
                  Text(
                    '${t.day}',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: soon ? Colors.white : Brand.forest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$when · ${DateFormat('h:mm a').format(t)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Brand.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final b in route.barangays)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: highlight.contains(b)
                                ? Brand.kraftLight
                                : Brand.paper,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: highlight.contains(b)
                                  ? Brand.kraft
                                  : Brand.line,
                            ),
                          ),
                          child: Text(
                            route.areaLabel(b),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: highlight.contains(b)
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: Brand.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (onDelete == null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping,
                          size: 18,
                          color: Brand.inkSoft,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            route.collectorName,
                            style: const TextStyle(
                              fontSize: 15.5,
                              color: Brand.inkSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (route.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“${route.note}”',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontStyle: FontStyle.italic,
                        color: Brand.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                iconSize: 28,
                tooltip: 'Cancel route',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Brand.danger),
              ),
          ],
        ),
      ),
    );
  }
}
