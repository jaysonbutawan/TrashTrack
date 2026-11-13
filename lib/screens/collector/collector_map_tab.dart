import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../models/route_schedule.dart';
import '../../route_planner.dart';
import '../../theme.dart';
import '../../widgets/barangay_demand.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import '../../widgets/tagum_map.dart';
import '../common/post_detail_screen.dart';

class CollectorMapTab extends StatefulWidget {
  const CollectorMapTab({super.key, required this.user});
  final AppUser user;

  @override
  State<CollectorMapTab> createState() => _CollectorMapTabState();
}

class _CollectorMapTabState extends State<CollectorMapTab> {
  final _map = MapController();
  late final Stream<List<RecyclablePost>> _posts = context
      .read<PostRepository>()
      .availablePosts();

  /// Upcoming routes of all collectors, to show which barangays are covered.
  List<RouteSchedule> _routes = const [];
  StreamSubscription<List<RouteSchedule>>? _routesSub;

  @override
  void initState() {
    super.initState();
    _routesSub = context
        .read<RouteRepository>()
        .routesFor(tagumBarangays)
        .listen((r) {
          if (mounted) setState(() => _routes = r);
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _routesSub?.cancel();
    super.dispose();
  }

  Future<void> _showBusy(List<BarangayDemand> ranking) async {
    final picked = await showBusyBarangays(context, ranking);
    if (picked != null) _map.move(picked.center, 15);
  }

  /// Empty = show all types.
  final Set<RecyclableType> _types = {};

  /// Null = show both For Sale and Free.
  PostLabel? _label;

  bool _matches(RecyclablePost p) =>
      (_label == null || p.label == _label) &&
      (_types.isEmpty || p.types.any(_types.contains));

  /// Where the collector is, once they tap "my location".
  LatLng? _me;

  Future<void> _goToMe() async {
    final messenger = ScaffoldMessenger.of(context);
    final (loc, err) = await currentLocation();
    if (loc == null) {
      showMessage(messenger, err!, error: true);
    } else if (!isInsideTagum(loc)) {
      showMessage(messenger, 'You are outside Tagum City.', error: true);
    } else {
      setState(() => _me = loc);
      _map.move(loc, 16);
    }
  }

  void _showSummary(RecyclablePost p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PostCard(
                post: p,
                onTap: () {
                  Navigator.pop(ctx);
                  openPostDetail(context, p.id);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openPostDetail(context, p.id);
                  },
                  icon: const Icon(Icons.visibility),
                  label: const Text('View & Reserve'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final l in [null, PostLabel.forSale, PostLabel.free])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(l?.label ?? 'All'),
                        selected: _label == l,
                        onSelected: (_) => setState(() => _label = l),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final t in RecyclableType.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(t.label),
                        selected: _types.contains(t),
                        onSelected: (v) => setState(
                          () => v ? _types.add(t) : _types.remove(t),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filters(),
        Expanded(
          child: StreamBuilder<List<RecyclablePost>>(
            stream: _posts,
            builder: (context, snap) {
              final shown = (snap.data ?? []).where(_matches).toList();
              final ranking = rankBarangays(snap.data ?? const [], _routes);
              return Stack(
                children: [
                  TagumMap(
                    controller: _map,
                    markers: [
                      if (_me != null) MyLocationDot.marker(_me!),
                      for (final p in shown)
                        Marker(
                          point: p.location,
                          width: 54,
                          height: 54,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => _showSummary(p),
                            child: Icon(
                              Icons.location_pin,
                              size: 54,
                              color: p.label == PostLabel.free
                                  ? Colors.teal.shade600
                                  : Colors.indigo.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          snap.hasError
                              ? 'Could not load posts'
                              : !snap.hasData
                              ? 'Loading…'
                              : '${shown.length} available',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 10,
                    right: 10,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Legend(Colors.indigo, 'For Sale'),
                            _Legend(Colors.teal, 'Free'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (ranking.isNotEmpty)
                    Positioned(
                      bottom: 16,
                      left: 12,
                      right: 130,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _BusyButton(
                          top: ranking.first,
                          onTap: () => _showBusy(ranking),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.large(
                      heroTag: 'me',
                      tooltip: 'My location',
                      onPressed: _goToMe,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.text);
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.location_pin, color: color, size: 22),
      Text(text, style: const TextStyle(fontSize: 15)),
    ],
  );
}

/// "Busiest: Apokon · 5 posts" — opens the barangay ranking.
class _BusyButton extends StatelessWidget {
  const _BusyButton({required this.top, required this.onTap});
  final BarangayDemand top;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Brand.card,
    elevation: 4,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Brand.kraft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_fire_department,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Busiest: ${top.barangay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: Brand.ink,
                    ),
                  ),
                  Text(
                    '${demandSummary(top)} · see all',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Brand.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
