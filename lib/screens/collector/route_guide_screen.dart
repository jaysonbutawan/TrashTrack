import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../route_planner.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/recyclable_style.dart';
import '../../widgets/tagum_map.dart';
import '../common/post_detail_screen.dart';

typedef Locator = Future<(LatLng?, String?)> Function();

/// Shortest route through the collector's reserved pickups, starting from
/// where they are now: numbered stops on the map, distance and time, and a
/// button that hands the whole trip to Google Maps for turn-by-turn.
class RouteGuideScreen extends StatefulWidget {
  const RouteGuideScreen({super.key, this.locate = currentLocation});

  /// Replaceable in tests (the real one needs the GPS plugin).
  final Locator locate;

  @override
  State<RouteGuideScreen> createState() => _RouteGuideScreenState();
}

class _RouteGuideScreenState extends State<RouteGuideScreen> {
  final _map = MapController();
  late final Stream<List<RecyclablePost>> _posts = context
      .read<PostRepository>()
      .reservedBy(context.read<AppUser>().id);

  LatLng? _me;
  String? _locationProblem;
  bool _locating = true;

  /// Identifies the route currently framed on the map, to re-frame on change.
  String _framed = '';

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    LatLng? loc;
    String? problem;
    try {
      (loc, problem) = await widget.locate();
      if (loc != null && !isInsideTagum(loc)) {
        loc = null;
        problem = 'You are outside Tagum City.';
      }
    } catch (_) {
      problem = 'Could not get your location.';
    }
    if (!mounted) return;
    setState(() {
      _me = loc;
      _locationProblem = problem;
      _locating = false;
    });
  }

  void _frame(PlannedRoute route) {
    final key = route.path.map((p) => '${p.latitude},${p.longitude}').join('|');
    if (key == _framed || route.stops.isEmpty) return;
    _framed = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.fitCamera(
          CameraFit.coordinates(
            coordinates: route.path,
            padding: const EdgeInsets.fromLTRB(48, 56, 48, 36),
            maxZoom: 16,
          ),
        );
      } catch (_) {
        // Map not laid out yet; it will be framed on the next change.
        _framed = '';
      }
    });
  }

  /// Opens Google Maps with every stop in order (it allows 9 in-between
  /// stops, so at most the first 10 pickups).
  Future<void> _navigateAll(PlannedRoute route) async {
    final stops = route.stops.take(10).toList();
    String ll(LatLng p) => '${p.latitude},${p.longitude}';
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (_me != null) 'origin': ll(_me!),
      'destination': ll(stops.last.location),
      if (stops.length > 1)
        'waypoints': stops
            .take(stops.length - 1)
            .map((s) => ll(s.location))
            .join('|'),
      'travelmode': 'driving',
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showMessage(
        ScaffoldMessenger.of(context),
        'Cannot open Google Maps.',
        error: true,
      );
    }
  }

  Future<void> _collected(RecyclablePost p) async {
    final posts = context.read<PostRepository>();
    if (await confirm(
          context,
          'Mark as collected?',
          'Did you already pick up these recyclables?',
        ) &&
        mounted) {
      await runWithFeedback(
        context,
        () => posts.markCollected(p.id),
        successMessage: 'Collected. Route updated.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Guide'),
        actions: [
          IconButton(
            tooltip: 'Update my location',
            iconSize: 28,
            onPressed: _locating ? null : _locate,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: StreamBuilder<List<RecyclablePost>>(
        stream: _posts,
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyMessage(Icons.wifi_off, 'Could not load.');
          }
          if (!snap.hasData || (_locating && _me == null)) {
            return const Center(child: CircularProgressIndicator());
          }
          final reserved = snap.data!;
          if (reserved.isEmpty) {
            return const EmptyMessage(
              Icons.route,
              'No pickups to plan.\nReserve posts on the Map first.',
            );
          }
          // Without GPS the route starts from the city center.
          final route = planRoute(_me ?? tagumCenter, reserved);
          _frame(route);
          return Column(
            children: [
              SizedBox(height: 250, child: _RouteMap(_map, route, _me)),
              _Summary(route: route),
              if (_locationProblem != null)
                _LocationNotice(_locationProblem!, onRetry: _locate),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  itemCount: route.stops.length,
                  itemBuilder: (context, i) => _StopTile(
                    number: i + 1,
                    post: route.stops[i],
                    legMeters: route.legMeters[i],
                    fromYou: i == 0 && _me != null,
                    onCollected: () => _collected(route.stops[i]),
                  ),
                ),
              ),
              _StartBar(
                stops: route.stops.length,
                onPressed: () => _navigateAll(route),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RouteMap extends StatelessWidget {
  const _RouteMap(this.controller, this.route, this.me);
  final MapController controller;
  final PlannedRoute route;
  final LatLng? me;

  @override
  Widget build(BuildContext context) {
    return TagumMap(
      controller: controller,
      initialCenter: route.stops.first.location,
      initialZoom: 14,
      polylines: [
        Polyline(
          points: route.path,
          strokeWidth: 5,
          color: Brand.forest.withValues(alpha: 0.85),
          borderStrokeWidth: 2,
          borderColor: Colors.white,
        ),
      ],
      markers: [
        if (me != null)
          Marker(
            point: me!,
            width: 26,
            height: 26,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
            ),
          ),
        for (var i = 0; i < route.stops.length; i++)
          Marker(
            point: route.stops[i].location,
            width: 36,
            height: 36,
            child: _NumberBadge(i + 1, next: i == 0, shadow: true),
          ),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.n, {this.next = false, this.shadow = false});
  final int n;
  final bool next;
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: next ? Brand.kraft : Brand.forest,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2.5),
      boxShadow: shadow
          ? const [BoxShadow(color: Colors.black38, blurRadius: 4)]
          : null,
    ),
    child: Text(
      '$n',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.route});
  final PlannedRoute route;

  Widget _cell(IconData icon, String value, String label) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    color: Brand.forest,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Row(
      children: [
        _cell(
          Icons.flag,
          '${route.stops.length}',
          route.stops.length == 1 ? 'stop' : 'stops',
        ),
        _cell(Icons.route, formatDistance(route.totalMeters), 'shortest route'),
        _cell(Icons.schedule, formatMinutes(route.totalMinutes), 'estimated'),
        _cell(Icons.scale, formatKg(route.totalKg), 'to collect'),
      ],
    ),
  );
}

class _LocationNotice extends StatelessWidget {
  const _LocationNotice(this.problem, {required this.onRetry});
  final String problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    color: Brand.kraftLight,
    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
    child: Row(
      children: [
        const Icon(Icons.location_off, color: Brand.kraft),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$problem The route starts from the city center for now.',
            style: const TextStyle(fontSize: 14.5, color: Brand.ink),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.number,
    required this.post,
    required this.legMeters,
    required this.fromYou,
    required this.onCollected,
  });

  final int number;
  final RecyclablePost post;
  final double legMeters;
  final bool fromYou;
  final VoidCallback onCollected;

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: TextButton.icon(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, overflow: TextOverflow.ellipsis),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = post;
    final next = number == 1;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: next ? Brand.kraft : Brand.line,
          width: next ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPostDetail(context, p.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NumberBadge(number, next: next),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (next)
                          const Text(
                            'NEXT STOP',
                            style: TextStyle(
                              fontSize: 12.5,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w900,
                              color: Brand.kraft,
                            ),
                          ),
                        Text(
                          p.types.map((t) => t.shortLabel).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
                          ),
                        ),
                        Text(
                          '${p.amount} · ${p.barangay} · ${p.householdName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Brand.inkSoft,
                          ),
                        ),
                        if (p.notes.isNotEmpty)
                          Text(
                            '“${p.notes}”',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontStyle: FontStyle.italic,
                              color: Brand.ink,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatDistance(legMeters),
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: Brand.forest,
                        ),
                      ),
                      Text(
                        fromYou
                            ? 'from you'
                            : number == 1
                            ? 'from center'
                            : 'from stop ${number - 1}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Brand.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(),
              Row(
                children: [
                  _action(Icons.directions, 'Go', () => openDirections(p)),
                  _action(
                    Icons.call,
                    'Call',
                    () => callPhone(context, p.householdPhone),
                  ),
                  _action(Icons.check_circle, 'Collected', onCollected),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartBar extends StatelessWidget {
  const _StartBar({required this.stops, required this.onPressed});
  final int stops;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Brand.card,
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.navigation),
              label: Text(
                stops == 1
                    ? 'Start Navigation'
                    : 'Start Navigation (All Stops)',
              ),
            ),
            if (stops > 10)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Google Maps takes 10 stops at a time. Start again after them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Brand.inkSoft),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
