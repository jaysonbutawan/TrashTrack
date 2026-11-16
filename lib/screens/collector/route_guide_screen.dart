import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../road_routing.dart';
import '../../route_planner.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/recyclable_style.dart';
import '../../widgets/tagum_map.dart';
import '../common/post_detail_screen.dart';

typedef Locator = Future<(LatLng?, String?)> Function();

/// How many nearby posts the suggested route visits when nothing is reserved.
const int suggestedStops = 5;

/// Opens the Route Guide. With [target] it shows the way to that one post —
/// no reservation needed, so the collector can check the trip first.
void openRouteGuide(BuildContext context, {RecyclablePost? target}) {
  final user = context.read<AppUser>();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Provider.value(
        value: user,
        child: RouteGuideScreen(target: target),
      ),
    ),
  );
}

enum _Mode {
  /// Way to a single post the collector is looking at.
  preview,

  /// Shortest order through the collector's reservations.
  reserved,

  /// Nothing reserved: shortest route through the nearest available posts.
  suggested,
}

/// Shortest route through the collector's pickups, starting from where they
/// are right now: real roads, live (or estimated) traffic with the fastest
/// road suggested, a GPS dot that follows the collector, and a button that
/// hands the trip to Google Maps for turn-by-turn.
class RouteGuideScreen extends StatefulWidget {
  const RouteGuideScreen({
    super.key,
    this.locate = currentLocation,
    this.track = liveLocation,
    this.target,
    this.router,
  });

  /// First quick fix. Replaceable in tests (the real one needs the GPS plugin).
  final Locator locate;

  /// Continuous GPS for the live dot.
  final LiveLocator track;

  /// Show the way to this post only (it does not need to be reserved).
  final RecyclablePost? target;

  /// Defaults to [RoadRouter.instance].
  final RoadRouter? router;

  @override
  State<RouteGuideScreen> createState() => _RouteGuideScreenState();
}

class _RouteGuideScreenState extends State<RouteGuideScreen> {
  final _map = MapController();
  final _subs = <StreamSubscription<dynamic>>[];
  late final RoadRouter _router = widget.router ?? RoadRouter.instance;

  List<RecyclablePost>? _reserved;
  List<RecyclablePost> _available = const [];
  RecyclablePost? _target;
  bool _targetGone = false;
  Object? _loadError;

  LatLng? _me;
  GpsFix? _fix;
  String? _locationProblem;
  bool _locating = true;

  /// Keep the map centered on the collector as they move.
  bool _follow = false;

  /// Identifies the route currently framed on the map, to re-frame on change.
  String _framed = '';

  // Road route for the current plan.
  RouteChoice? _road;
  int _picked = 0;
  bool _roadLoading = false;
  String _roadFor = '';
  LatLng? _roadFrom;
  DateTime _roadAt = DateTime(2000);
  Timer? _trafficTimer;

  /// Re-route after moving this far, and refresh traffic this often.
  static const _rerouteMeters = 80.0;
  static const _trafficEvery = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    final posts = context.read<PostRepository>();
    _target = widget.target;
    if (widget.target != null) {
      _subs.add(
        posts.watch(widget.target!.id).listen((p) {
          if (!mounted) return;
          setState(() {
            _targetGone = p == null || p.status == PostStatus.collected;
            if (p != null) _target = p;
          });
        }, onError: (_) {}),
      );
    } else {
      _subs
        ..add(
          posts
              .reservedBy(context.read<AppUser>().id)
              .listen(
                (r) => mounted ? setState(() => _reserved = r) : null,
                onError: (Object e) =>
                    mounted ? setState(() => _loadError = e) : null,
              ),
        )
        ..add(
          posts.availablePosts().listen(
            (a) => mounted ? setState(() => _available = a) : null,
            onError: (_) {},
          ),
        );
    }
    _locate();
    _subs.add(
      widget.track().listen(
        _onFix,
        // The one-shot locate already explains GPS problems.
        onError: (_) {},
      ),
    );
    _trafficTimer = Timer.periodic(_trafficEvery, (_) {
      // Forces a fresh request with current traffic on the next build.
      if (mounted) setState(() => _roadFor = '');
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _trafficTimer?.cancel();
    super.dispose();
  }

  void _onFix(GpsFix fix) {
    if (!mounted || !isInsideTagum(fix.point)) return;
    setState(() {
      _fix = fix;
      _me = fix.point;
      _locationProblem = null;
      _locating = false;
    });
    if (_follow) _moveMap(fix.point, null);
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    LatLng? loc;
    String? problem;
    try {
      // GPS can take very long indoors; don't keep the collector waiting.
      (loc, problem) = await widget.locate().timeout(
        const Duration(seconds: 12),
      );
      if (loc != null && !isInsideTagum(loc)) {
        loc = null;
        problem = 'You are outside Tagum City.';
      }
    } catch (_) {
      problem = 'Could not get your location.';
    }
    if (!mounted) return;
    setState(() {
      // Keep the last known position if this attempt failed.
      _me = loc ?? _me;
      _locationProblem = _me == null ? problem : null;
      _locating = false;
    });
  }

  void _moveMap(LatLng to, double? zoom) {
    try {
      _map.move(to, zoom ?? _map.camera.zoom);
    } catch (_) {
      // Map not laid out yet.
    }
  }

  void _toggleFollow() {
    final me = _me;
    if (me == null) {
      _locate();
      return;
    }
    setState(() => _follow = !_follow);
    if (_follow) _moveMap(me, 17);
  }

  // ---- What to visit -------------------------------------------------------

  _Mode get _mode => widget.target != null
      ? _Mode.preview
      : (_reserved?.isNotEmpty ?? false)
      ? _Mode.reserved
      : _Mode.suggested;

  List<RecyclablePost> _stops(LatLng from) => switch (_mode) {
    _Mode.preview => [if (_target != null && !_targetGone) _target!],
    _Mode.reserved => _reserved!,
    _Mode.suggested => nearestAvailable(_available, from, suggestedStops),
  };

  // ---- Road route ----------------------------------------------------------

  void _ensureRoad(PlannedRoute plan) {
    if (plan.stops.isEmpty) return;
    final key = plan.stops.map((s) => s.id).join(',');
    final moved =
        _roadFrom == null ||
        metersBetween(_roadFrom!, plan.start) > _rerouteMeters;
    if (_roadLoading || (key == _roadFor && !moved)) return;
    // Don't hammer the provider while GPS jitters.
    if (key == _roadFor &&
        DateTime.now().difference(_roadAt) < const Duration(seconds: 20)) {
      return;
    }
    _roadLoading = true;
    _roadFor = key;
    _roadFrom = plan.start;
    _roadAt = DateTime.now();
    final waypoints = plan.path.take(21).toList(); // provider limits
    _router
        .route(waypoints, alternatives: plan.stops.length == 1)
        .then((routes) {
          if (!mounted) return;
          setState(() {
            _roadLoading = false;
            if (routes.isNotEmpty) {
              final previous = _road;
              _road = RouteChoice(routes);
              // Keep the collector's chosen road unless the plan changed.
              if (previous == null || _picked >= _road!.options.length) {
                _picked = 0;
              }
            }
          });
        })
        .catchError((Object _) {
          if (!mounted) return;
          // Offline / provider down: keep straight lines, try again later.
          setState(() => _roadLoading = false);
        });
  }

  RoadRoute? _roadForPlan(PlannedRoute plan) {
    final key = plan.stops.map((s) => s.id).join(',');
    if (_road == null || key != _roadFor) return null;
    return _road!.options[_picked.clamp(0, _road!.options.length - 1)];
  }

  void _frame(PlannedRoute route) {
    if (_follow) return;
    final key = '${_me != null}|${route.stops.map((s) => s.id).join('|')}';
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

  // ---- Actions -------------------------------------------------------------

  /// Opens Google Maps with every stop in order (it allows 9 in-between
  /// stops, so at most the first 10 pickups). Google adds its own live
  /// traffic and turn-by-turn voice.
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

  Future<void> _reserve(RecyclablePost p) => runWithFeedback(
    context,
    () => context.read<PostRepository>().reserve(p.id),
    successMessage: 'Reserved! Others can no longer take it.',
  );

  // ---- UI ------------------------------------------------------------------

  String get _title => switch (_mode) {
    _Mode.preview => 'Route to Pickup',
    _Mode.reserved => 'Route Guide',
    _Mode.suggested => 'Suggested Route',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Update my location',
            iconSize: 28,
            onPressed: _locating ? null : _locate,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return const EmptyMessage(Icons.wifi_off, 'Could not load.');
    }
    if (_mode != _Mode.preview && _reserved == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final from = _me ?? tagumCenter;
    final stops = _stops(from);
    if (stops.isEmpty) {
      return EmptyMessage(
        Icons.route,
        _mode == _Mode.preview
            ? 'This post was already collected or removed.'
            : 'No pickups to plan.\nThere are no available posts right now.',
      );
    }
    // The route shows right away and is redrawn when GPS answers;
    // until then (or without GPS) it starts from the city center.
    final plan = planRoute(from, stops);
    _frame(plan);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureRoad(plan);
    });
    final road = _roadForPlan(plan);
    final reservedByOther =
        _mode == _Mode.preview &&
        _target!.status == PostStatus.reserved &&
        _target!.reservedBy != context.read<AppUser>().id;

    return Column(
      children: [
        SizedBox(
          height: 250,
          child: Stack(
            children: [
              _RouteMap(
                controller: _map,
                plan: plan,
                fix: _fix,
                me: _me,
                choice: road == null ? null : _road,
                picked: _picked,
                onPick: (i) => setState(() => _picked = i),
                onDragged: () {
                  if (_follow) setState(() => _follow = false);
                },
              ),
              Positioned(
                right: 10,
                bottom: 14,
                child: FloatingActionButton.small(
                  heroTag: 'follow',
                  tooltip: _follow ? 'Stop following me' : 'Follow me',
                  backgroundColor: _follow ? const Color(0xFF1A73E8) : null,
                  foregroundColor: _follow ? Colors.white : null,
                  onPressed: _toggleFollow,
                  child: Icon(
                    _follow ? Icons.navigation : Icons.near_me_outlined,
                  ),
                ),
              ),
              if (_fix != null)
                Positioned(left: 10, top: 10, child: _LiveBadge(_fix!)),
            ],
          ),
        ),
        _Summary(plan: plan, road: road),
        if (_me == null && _locating)
          const _LocationNotice('Finding your location…')
        else if (_me == null && _locationProblem != null)
          _LocationNotice(_locationProblem!, onRetry: _locate),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            children: [
              if (_mode == _Mode.suggested)
                _InfoBanner(
                  icon: Icons.tips_and_updates,
                  text:
                      'No reservations yet: shortest route through the '
                      '${plan.stops.length} nearest pickups. Reserve before going.',
                ),
              if (reservedByOther)
                const _InfoBanner(
                  icon: Icons.lock_clock,
                  text: 'Another collector already reserved this post.',
                  warning: true,
                ),
              _TrafficCard(
                choice: road == null ? null : _road,
                picked: _picked,
                loading: _roadLoading && road == null,
                live: _router.hasLiveTraffic,
                onPick: (i) => setState(() => _picked = i),
              ),
              for (var i = 0; i < plan.stops.length; i++)
                _StopTile(
                  number: i + 1,
                  post: plan.stops[i],
                  legMeters: plan.legMeters[i],
                  fromYou: i == 0 && _me != null,
                  reservedByMe:
                      plan.stops[i].status == PostStatus.reserved &&
                      plan.stops[i].reservedBy == context.read<AppUser>().id,
                  onCollected: () => _collected(plan.stops[i]),
                  onReserve: () => _reserve(plan.stops[i]),
                ),
            ],
          ),
        ),
        _StartBar(
          stops: plan.stops.length,
          onPressed: () => _navigateAll(plan),
        ),
      ],
    );
  }
}

/// The [count] available posts closest to [from], for a route when the
/// collector has not reserved anything yet.
List<RecyclablePost> nearestAvailable(
  List<RecyclablePost> posts,
  LatLng from,
  int count,
) {
  final list = posts.where((p) => p.status == PostStatus.available).toList()
    ..sort(
      (a, b) => metersBetween(
        from,
        a.location,
      ).compareTo(metersBetween(from, b.location)),
    );
  return list.take(count).toList();
}

Color trafficColor(TrafficLevel t) => switch (t) {
  TrafficLevel.light => const Color(0xFF2E7D32),
  TrafficLevel.moderate => const Color(0xFFEF8F00),
  TrafficLevel.heavy => const Color(0xFFC62828),
};

class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.controller,
    required this.plan,
    required this.fix,
    required this.me,
    required this.choice,
    required this.picked,
    required this.onPick,
    required this.onDragged,
  });
  final MapController controller;
  final PlannedRoute plan;
  final GpsFix? fix;
  final LatLng? me;
  final RouteChoice? choice;
  final int picked;
  final ValueChanged<int> onPick;
  final VoidCallback onDragged;

  @override
  Widget build(BuildContext context) {
    final options = choice?.options ?? const <RoadRoute>[];
    final chosen = options.isEmpty ? null : options[picked];
    return TagumMap(
      controller: controller,
      initialCenter: plan.stops.first.location,
      initialZoom: 14,
      maxZoom: 19,
      onCameraMoved: (_, byUser) {
        if (byUser) onDragged();
      },
      circles: [if (fix != null) fix!.accuracyCircle],
      polylines: [
        // Other roads, grey, under the chosen one.
        for (var i = 0; i < options.length; i++)
          if (i != picked)
            Polyline(
              points: options[i].points,
              strokeWidth: 5,
              color: Colors.blueGrey.withValues(alpha: 0.55),
              borderStrokeWidth: 1.5,
              borderColor: Colors.white,
            ),
        Polyline(
          points: chosen?.points ?? plan.path,
          strokeWidth: 6,
          color: (chosen == null ? Brand.forest : trafficColor(chosen.traffic))
              .withValues(alpha: 0.9),
          borderStrokeWidth: 2,
          borderColor: Colors.white,
          pattern: chosen == null
              ? StrokePattern.dashed(segments: const [12, 8])
              : const StrokePattern.solid(),
        ),
      ],
      markers: [
        for (var i = 0; i < plan.stops.length; i++)
          Marker(
            point: plan.stops[i].location,
            width: 36,
            height: 36,
            child: _NumberBadge(i + 1, next: i == 0, shadow: true),
          ),
        if (fix != null)
          LiveLocationDot.marker(fix!)
        else if (me != null)
          MyLocationDot.marker(me!),
      ],
    );
  }
}

/// "LIVE ±8 m" — shows the dot is the collector's real-time position.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge(this.fix);
  final GpsFix fix;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: Color(0xFF1A73E8),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE ${fix.accuracyLabel}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Brand.ink,
            ),
          ),
        ],
      ),
    ),
  );
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
  const _Summary({required this.plan, required this.road});
  final PlannedRoute plan;

  /// Real road route once it arrives; straight-line estimate until then.
  final RoadRoute? road;

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
  Widget build(BuildContext context) {
    final meters = road?.meters ?? plan.totalMeters;
    final minutes = road == null
        ? plan.totalMinutes
        : road!.minutes + plan.stops.length * minutesPerStop;
    return Container(
      color: Brand.forest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          _cell(
            Icons.flag,
            '${plan.stops.length}',
            plan.stops.length == 1 ? 'stop' : 'stops',
          ),
          _cell(Icons.route, formatDistance(meters), 'shortest route'),
          _cell(Icons.schedule, formatMinutes(minutes), 'estimated'),
          _cell(Icons.scale, formatKg(plan.totalKg), 'to collect'),
        ],
      ),
    );
  }
}

/// Traffic now, and which road to take.
class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.choice,
    required this.picked,
    required this.loading,
    required this.live,
    required this.onPick,
  });
  final RouteChoice? choice;
  final int picked;
  final bool loading;
  final bool live;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = choice;
    if (c == null) {
      return _InfoBanner(
        icon: Icons.traffic,
        text: loading
            ? 'Checking roads and traffic…'
            : 'Road route unavailable offline. Showing straight lines.',
      );
    }
    final best = c.best;
    final source = best.liveTraffic
        ? 'Live traffic'
        : 'Estimated traffic (rush hours)';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.traffic, color: trafficColor(best.traffic)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: best.traffic.label,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: trafficColor(best.traffic),
                          ),
                        ),
                        TextSpan(
                          text: '  $source',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c.avoidsTraffic
                  ? 'Suggested: the fastest road avoids traffic and saves '
                        '${c.minutesSavedVsShortest} min vs the shortest road.'
                  : best.trafficSeconds >= 60
                  ? 'Traffic adds about ${(best.trafficSeconds / 60).round()} '
                        'min. This is still the best road.'
                  : 'Roads are clear. Take the suggested route.',
              style: const TextStyle(fontSize: 14.5, color: Brand.ink),
            ),
            if (c.options.length > 1) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < c.options.length; i++)
                _RoadOption(
                  route: c.options[i],
                  title: i == 0
                      ? 'Fastest now'
                      : identical(c.options[i], c.shortest)
                      ? 'Shortest distance'
                      : 'Other road',
                  selected: i == picked,
                  onTap: () => onPick(i),
                ),
            ],
            if (!live)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Start Navigation opens Google Maps with live traffic.',
                  style: TextStyle(fontSize: 12.5, color: Brand.inkSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoadOption extends StatelessWidget {
  const _RoadOption({
    required this.route,
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final RoadRoute route;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? Brand.forest : Brand.inkSoft,
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: trafficColor(route.traffic),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              route.summary.isEmpty ? title : '$title · ${route.summary}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: Brand.ink),
            ),
          ),
          Text(
            '${formatMinutes(route.minutes)} · ${formatDistance(route.meters)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Brand.forest,
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    this.warning = false,
  });
  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFDECEA) : Brand.mint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: warning ? Brand.danger : Brand.forest),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14.5, color: Brand.ink),
          ),
        ),
      ],
    ),
  );
}

class _LocationNotice extends StatelessWidget {
  const _LocationNotice(this.problem, {this.onRetry});
  final String problem;

  /// Null while still searching (shows a small spinner instead).
  final VoidCallback? onRetry;

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
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry'))
        else
          const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
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
    required this.reservedByMe,
    required this.onCollected,
    required this.onReserve,
  });

  final int number;
  final RecyclablePost post;
  final double legMeters;
  final bool fromYou;
  final bool reservedByMe;
  final VoidCallback onCollected;
  final VoidCallback onReserve;

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
                  if (reservedByMe) ...[
                    _action(
                      Icons.call,
                      'Call',
                      () => callPhone(context, p.householdPhone),
                    ),
                    _action(Icons.check_circle, 'Collected', onCollected),
                  ] else if (p.status == PostStatus.available)
                    _action(Icons.bookmark_add, 'Reserve', onReserve),
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
