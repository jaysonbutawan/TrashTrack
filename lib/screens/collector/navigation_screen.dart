import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../models/post.dart';
import '../../road_routing.dart';
import '../../route_planner.dart';
import '../../theme.dart';
import '../../widgets/cancel_reservation.dart';
import '../../widgets/common.dart';
import '../../widgets/tagum_map.dart';
import '../common/post_detail_screen.dart';
import 'route_guide_screen.dart' show trafficColor;

/// Speaks turn instructions. Replaceable in tests.
abstract class Speaker {
  Future<void> say(String text);
  Future<void> stop();
}

/// Device text-to-speech (English, falling back to the phone's default).
class TtsSpeaker implements Speaker {
  TtsSpeaker() {
    _ready = () async {
      try {
        await _tts.setLanguage('en-US');
        await _tts.setSpeechRate(0.5);
        await _tts.awaitSpeakCompletion(false);
      } catch (_) {
        // Keep the phone's default voice.
      }
    }();
  }

  final _tts = FlutterTts();
  late final Future<void> _ready;

  @override
  Future<void> say(String text) async {
    try {
      await _ready;
      await _tts.speak(text);
    } catch (_) {
      // No TTS engine: the banner still shows the turn.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Opens turn-by-turn navigation through [stops], in this order.
void openNavigation(BuildContext context, List<RecyclablePost> stops) {
  final user = context.read<AppUser>();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Provider.value(
        value: user,
        child: NavigationScreen(stops: stops),
      ),
    ),
  );
}

/// In-app turn-by-turn: the map follows the collector, the next turn is
/// shown on top and spoken, it re-routes when they leave the road, and on
/// reaching a stop it asks whether it was collected.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.stops,
    this.track = liveLocation,
    this.router,
    this.speaker,
    this.keepAwake = true,
    this.rerouteEvery = const Duration(seconds: 15),
  });

  final List<RecyclablePost> stops;
  final LiveLocator track;

  /// Defaults to [RoadRouter.instance].
  final RoadRouter? router;

  /// Defaults to the phone's text-to-speech.
  final Speaker? speaker;

  /// Keep the screen on while navigating (off in tests).
  final bool keepAwake;

  /// At most one re-route this often.
  final Duration rerouteEvery;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  /// Off the road by more than this, twice in a row → re-route.
  static const offRouteMeters = 40.0;

  /// Closer than this to a stop → arrived.
  static const arriveMeters = 30.0;

  /// A maneuver counts as done once this close to it.
  static const passedMeters = 20.0;

  final _map = MapController();
  late final RoadRouter _router = widget.router ?? RoadRouter.instance;
  late final Speaker _speaker = widget.speaker ?? TtsSpeaker();
  StreamSubscription<GpsFix>? _gps;

  GpsFix? _fix;
  String? _gpsProblem;
  RoadRoute? _route;
  bool _routing = false;
  DateTime _routedAt = DateTime(2000);
  int _offCount = 0;

  /// Index into [widget.stops] of where we are heading.
  int _stop = 0;

  /// Index into the route's steps of the next maneuver.
  int _step = 0;

  /// Steps already announced at each distance (400 / 100 / 0 m).
  final _spoken = <String>{};
  bool _muted = false;
  bool _follow = true;
  int? _arrivedAt;
  bool _finished = false;

  RecyclablePost get _target => widget.stops[_stop];

  @override
  void initState() {
    super.initState();
    if (widget.keepAwake) {
      WakelockPlus.enable().catchError((_) {});
    }
    _gps = widget.track().listen(
      _onFix,
      onError: (Object e) {
        if (mounted) {
          setState(
            () =>
                _gpsProblem = e is String ? e : 'Could not get your location.',
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _gps?.cancel();
    _speaker.stop();
    if (widget.keepAwake) {
      WakelockPlus.disable().catchError((_) {});
    }
    super.dispose();
  }

  void _say(String text) {
    if (!_muted) _speaker.say(text);
  }

  // ── Routing ──────────────────────────────────────────────────────────

  Future<void> _routeFrom(LatLng from, {bool reroute = false}) async {
    if (_routing || _finished) return;
    _routing = true;
    _routedAt = DateTime.now();
    if (reroute) _say('Rerouting');
    final waypoints = [
      from,
      for (final s in widget.stops.skip(_stop).take(20)) s.location,
    ];
    try {
      final routes = await _router.route(waypoints);
      if (!mounted) return;
      setState(() {
        _route = routes.isEmpty ? null : routes.first;
        // Skip the "Start on …" step; we are already moving.
        _step =
            (_route?.steps.isNotEmpty ?? false) &&
                _route!.steps.first.maneuver == 'depart' &&
                _route!.steps.length > 1
            ? 1
            : 0;
        _spoken.clear();
        _offCount = 0;
      });
    } catch (_) {
      // Keep the old route (or straight line) and try again later.
    } finally {
      _routing = false;
    }
  }

  List<NavStep> get _steps => _route?.steps ?? const [];

  NavStep? get _nextStep => _step < _steps.length ? _steps[_step] : null;

  // ── Each GPS reading ─────────────────────────────────────────────────

  void _onFix(GpsFix fix) {
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _gpsProblem = null;
    });
    if (_follow) _moveCamera(fix.point);
    if (_finished) return;

    final route = _route;
    if (route == null) {
      _routeFrom(fix.point);
      return;
    }

    // Left the road?
    if (route.points.length >= 2 &&
        metersToPath(fix.point, route.points) > offRouteMeters) {
      _offCount++;
      if (_offCount >= 2 &&
          DateTime.now().difference(_routedAt) >= widget.rerouteEvery) {
        _routeFrom(fix.point, reroute: true);
      }
    } else {
      _offCount = 0;
    }

    // Arrived at the stop?
    if (metersBetween(fix.point, _target.location) <= arriveMeters &&
        _arrivedAt != _stop) {
      _arrive();
      return;
    }

    _announce(fix.point);
  }

  void _announce(LatLng me) {
    var step = _nextStep;
    if (step == null) return;
    var d = metersBetween(me, step.point);
    // Passed this maneuver: move on to the next one.
    while (d <= passedMeters && !step!.isArrival) {
      if (_spoken.add('$_step@0')) _say(step.instruction);
      setState(() => _step++);
      step = _nextStep;
      if (step == null) return;
      d = metersBetween(me, step.point);
    }
    if (step!.isArrival) return; // handled by _arrive
    if (d <= 120 && _spoken.add('$_step@100')) {
      _say('In ${_roundMeters(d)} meters, ${step.instruction}');
    } else if (d <= 420 && d > 120 && _spoken.add('$_step@400')) {
      _say('In ${_roundMeters(d)} meters, ${step.instruction}');
    }
  }

  static int _roundMeters(double d) =>
      d >= 100 ? (d / 50).round() * 50 : (d / 10).round() * 10;

  void _moveCamera(LatLng p) {
    try {
      final zoom = _map.camera.zoom < 15 ? 17.0 : _map.camera.zoom;
      _map.move(p, zoom);
    } catch (_) {
      // Map not ready yet.
    }
  }

  // ── Stops ────────────────────────────────────────────────────────────

  Future<void> _arrive() async {
    setState(() => _arrivedAt = _stop);
    final p = _target;
    _say('You have arrived at stop ${_stop + 1}, ${p.householdName}');
    final next = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => Provider.value(
        value: context.read<AppUser>(),
        child: Provider.value(
          value: context.read<PostRepository>(),
          child: _ArrivedSheet(
            number: _stop + 1,
            post: p,
            isLast: _stop == widget.stops.length - 1,
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (next == true) _nextStop();
  }

  void _nextStop() {
    if (_stop >= widget.stops.length - 1) {
      setState(() => _finished = true);
      _say('All stops done. Great work!');
      return;
    }
    setState(() {
      _stop++;
      _route = null;
      _step = 0;
    });
    final me = _fix?.point;
    if (me != null) _routeFrom(me);
  }

  Future<void> _openGoogleMaps() async {
    String ll(LatLng p) => '${p.latitude},${p.longitude}';
    final rest = widget.stops.skip(_stop).take(10).toList();
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (_fix != null) 'origin': ll(_fix!.point),
      'destination': ll(rest.last.location),
      if (rest.length > 1)
        'waypoints': rest
            .take(rest.length - 1)
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

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final me = _fix?.point;
    final route = _route;
    final step = _nextStep;
    final toStep = me == null || step == null
        ? null
        : metersBetween(me, step.point);
    final left = me == null || route == null
        ? null
        : metersLeftOnPath(me, route.points);
    final minutesLeft = left == null || route == null || route.meters <= 0
        ? null
        : (route.seconds * (left / route.meters) / 60).ceil() +
              (widget.stops.length - _stop) * minutesPerStop;

    final instruction = _finished
        ? 'All stops done'
        : step == null || step.isArrival
        ? 'Head to stop ${_stop + 1} · ${_target.householdName}'
        : step.instruction;

    return Scaffold(
      body: Stack(
        children: [
          TagumMap(
            controller: _map,
            initialCenter: me ?? _target.location,
            initialZoom: 17,
            maxZoom: 19,
            onCameraMoved: (_, byUser) {
              if (byUser && _follow) setState(() => _follow = false);
            },
            circles: [if (_fix != null) _fix!.accuracyCircle],
            polylines: [
              if (route != null)
                Polyline(
                  points: route.points,
                  strokeWidth: 7,
                  color: trafficColor(route.traffic).withValues(alpha: 0.9),
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                ),
            ],
            markers: [
              for (var i = _stop; i < widget.stops.length; i++)
                Marker(
                  point: widget.stops[i].location,
                  width: 38,
                  height: 38,
                  child: _StopBadge(i + 1, current: i == _stop),
                ),
              if (_fix != null) LiveLocationDot.marker(_fix!),
            ],
          ),
          // Next turn.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _TurnBanner(
              icon: _finished
                  ? Icons.flag
                  : maneuverIcon(step?.maneuver ?? '', step?.instruction ?? ''),
              distance: toStep == null || _finished
                  ? null
                  : formatDistance(toStep),
              instruction: instruction,
              problem:
                  _gpsProblem ?? (me == null ? 'Finding your location…' : null),
            ),
          ),
          if (!_follow && me != null)
            Positioned(
              right: 14,
              bottom: 150,
              child: FloatingActionButton(
                heroTag: 'recenter',
                tooltip: 'Follow me',
                onPressed: () {
                  setState(() => _follow = true);
                  _moveCamera(me);
                },
                child: const Icon(Icons.navigation),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              stop: _stop + 1,
              of: widget.stops.length,
              name: _target.householdName,
              left: left == null ? null : formatDistance(left),
              minutes: minutesLeft == null ? null : formatMinutes(minutesLeft),
              muted: _muted,
              finished: _finished,
              onMute: () {
                setState(() => _muted = !_muted);
                if (_muted) _speaker.stop();
              },
              onGoogleMaps: _openGoogleMaps,
              onEnd: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Arrow for a maneuver.
IconData maneuverIcon(String maneuver, String instruction) {
  final t = '$maneuver ${instruction.toLowerCase()}';
  if (t.contains('arrive')) return Icons.flag;
  if (t.contains('u-turn') || t.contains('uturn')) return Icons.u_turn_left;
  if (t.contains('roundabout')) return Icons.roundabout_left;
  if (t.contains('slightly left') || t.contains('keep left')) {
    return Icons.turn_slight_left;
  }
  if (t.contains('slightly right') || t.contains('keep right')) {
    return Icons.turn_slight_right;
  }
  if (t.contains('sharp left')) return Icons.turn_sharp_left;
  if (t.contains('sharp right')) return Icons.turn_sharp_right;
  if (t.contains('left')) return Icons.turn_left;
  if (t.contains('right')) return Icons.turn_right;
  return Icons.straight;
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.icon,
    required this.distance,
    required this.instruction,
    required this.problem,
  });
  final IconData icon;
  final String? distance;
  final String instruction;
  final String? problem;

  @override
  Widget build(BuildContext context) => Material(
    color: Brand.forestDark,
    elevation: 6,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (distance != null)
                        Text(
                          distance!,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      Text(
                        instruction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: distance == null ? 21 : 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  problem!,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.stop,
    required this.of,
    required this.name,
    required this.left,
    required this.minutes,
    required this.muted,
    required this.finished,
    required this.onMute,
    required this.onGoogleMaps,
    required this.onEnd,
  });
  final int stop;
  final int of;
  final String name;
  final String? left;
  final String? minutes;
  final bool muted;
  final bool finished;
  final VoidCallback onMute;
  final VoidCallback onGoogleMaps;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Material(
    color: Brand.card,
    elevation: 10,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finished
                            ? 'Route finished'
                            : [?minutes, ?left].join(' · '),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Brand.forest,
                        ),
                      ),
                      Text(
                        finished
                            ? 'All $of stops done'
                            : 'Stop $stop of $of · $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Brand.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: muted ? 'Turn voice on' : 'Mute voice',
                  iconSize: 28,
                  onPressed: onMute,
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.danger,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: onEnd,
                  child: Text(finished ? 'Close' : 'End'),
                ),
              ],
            ),
            if (!finished)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onGoogleMaps,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _StopBadge extends StatelessWidget {
  const _StopBadge(this.n, {required this.current});
  final int n;
  final bool current;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: current ? Brand.kraft : Brand.forest,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2.5),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
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

/// "You've arrived at stop 1 · Maria Santos" with what to do now.
/// Pops true to go on to the next stop.
class _ArrivedSheet extends StatelessWidget {
  const _ArrivedSheet({
    required this.number,
    required this.post,
    required this.isLast,
  });
  final int number;
  final RecyclablePost post;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final mine =
        post.status == PostStatus.reserved &&
        post.reservedBy == context.read<AppUser>().id;
    final posts = context.read<PostRepository>();
    final nextLabel = isLast ? 'Finish' : 'Next Stop';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Brand.kraft, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You've arrived at stop $number",
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Brand.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${post.householdName} · ${post.area} · ${post.amount}',
              style: const TextStyle(fontSize: 15.5, color: Brand.inkSoft),
            ),
            const SizedBox(height: 14),
            if (mine) ...[
              FilledButton.icon(
                onPressed: () async {
                  if (await confirm(
                        context,
                        'Mark as collected?',
                        'Did you already pick up these recyclables?',
                      ) &&
                      context.mounted &&
                      await runWithFeedback(
                        context,
                        () => posts.markCollected(post.id),
                        successMessage: 'Collected. Salamat!',
                      ) &&
                      context.mounted) {
                    Navigator.pop(context, true);
                  }
                },
                icon: const Icon(Icons.check_circle),
                label: Text('Collected · $nextLabel'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => callPhone(context, post.householdPhone),
                      icon: const Icon(Icons.call),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.danger,
                        side: const BorderSide(color: Brand.danger),
                      ),
                      onPressed: () async {
                        if (await cancelReservationWithReason(context, post) &&
                            context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () => openPostDetail(context, post.id),
                icon: const Icon(Icons.visibility),
                label: const Text('View Post'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(mine ? 'Skip for now · $nextLabel' : nextLabel),
            ),
          ],
        ),
      ),
    );
  }
}
