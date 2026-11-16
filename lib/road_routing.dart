// Real road routes for collectors: the actual streets to drive, how long it
// takes right now, and which way avoids traffic.
//
// Two providers:
//  * TomTom (when TOMTOM_API_KEY is set in .env) — LIVE traffic: travel time
//    includes current jams, and it returns alternative roads to compare.
//  * OSRM (free, no key) — real roads and alternatives, but no live traffic,
//    so congestion is estimated from Tagum rush hours.
// Without network the app falls back to straight lines (StraightLineRouter).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'route_planner.dart';

enum TrafficLevel {
  light('Light traffic'),
  moderate('Moderate traffic'),
  heavy('Heavy traffic');

  const TrafficLevel(this.label);
  final String label;

  /// From the extra time traffic adds over a free-flowing road.
  static TrafficLevel fromDelay(double trafficSeconds, double freeSeconds) {
    if (freeSeconds <= 0) return light;
    final ratio = trafficSeconds / freeSeconds;
    if (ratio >= 0.35) return heavy;
    if (ratio >= 0.12) return moderate;
    return light;
  }
}

/// One way to drive through the waypoints.
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.meters,
    required this.freeFlowSeconds,
    required this.trafficSeconds,
    required this.liveTraffic,
    this.summary = '',
  });

  /// Road geometry to draw on the map.
  final List<LatLng> points;
  final double meters;

  /// Driving time on empty roads.
  final double freeFlowSeconds;

  /// Extra time caused by traffic (live from TomTom, estimated otherwise).
  final double trafficSeconds;

  /// True when [trafficSeconds] comes from live traffic data.
  final bool liveTraffic;

  /// Main roads used, e.g. "Apokon Road, National Highway" (may be empty).
  final String summary;

  double get seconds => freeFlowSeconds + trafficSeconds;
  int get minutes => (seconds / 60).ceil();
  TrafficLevel get traffic =>
      TrafficLevel.fromDelay(trafficSeconds, freeFlowSeconds);
}

/// Road routes from the first waypoint through the rest, in order.
abstract class RoadRouter {
  const RoadRouter();

  /// Used by the screens. `main()` replaces it with a real provider; tests
  /// keep the offline straight-line one.
  static RoadRouter instance = const StraightLineRouter();

  /// Picks TomTom (live traffic) when a key is given, otherwise OSRM.
  static RoadRouter fromKey(String tomTomKey) => tomTomKey.isEmpty
      ? OsrmRouter()
      : TomTomRouter(tomTomKey, fallback: OsrmRouter());

  bool get hasLiveTraffic;

  /// Best route first. With [alternatives] (only honoured for a single
  /// destination) other roads are returned too, for comparison.
  /// Throws on network / provider errors.
  Future<List<RoadRoute>> route(
    List<LatLng> waypoints, {
    bool alternatives = false,
  });
}

/// Rush-hour slowdown in Tagum when no live traffic is available: morning and
/// evening commute, and the lunch break around the city center.
double estimatedTrafficFactor(DateTime t) {
  final m = t.hour * 60 + t.minute;
  final weekend =
      t.weekday == DateTime.saturday || t.weekday == DateTime.sunday;
  bool between(int h1, int m1, int h2, int m2) =>
      m >= h1 * 60 + m1 && m < h2 * 60 + m2;
  if (between(6, 30, 8, 30) || between(16, 30, 18, 30)) {
    return weekend ? 0.15 : 0.45;
  }
  if (between(11, 30, 13, 0)) return 0.2;
  if (between(8, 30, 16, 30)) return 0.1;
  return 0.0;
}

/// Offline fallback: straight lines with the city road factor.
class StraightLineRouter extends RoadRouter {
  const StraightLineRouter();

  @override
  bool get hasLiveTraffic => false;

  @override
  Future<List<RoadRoute>> route(
    List<LatLng> waypoints, {
    bool alternatives = false,
  }) async {
    var meters = 0.0;
    for (var i = 1; i < waypoints.length; i++) {
      meters += metersBetween(waypoints[i - 1], waypoints[i]) * roadFactor;
    }
    final free = meters / 1000 / 18 * 3600;
    return [
      RoadRoute(
        points: waypoints,
        meters: meters,
        freeFlowSeconds: free,
        trafficSeconds: free * estimatedTrafficFactor(DateTime.now()),
        liveTraffic: false,
      ),
    ];
  }
}

/// Free OpenStreetMap routing (router.project-osrm.org). Fair-use only; for
/// many collectors host your own OSRM and pass its [baseUrl].
class OsrmRouter extends RoadRouter {
  OsrmRouter({
    this.baseUrl = 'https://router.project-osrm.org',
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final String baseUrl;
  final http.Client _client;
  final DateTime Function() _now;

  @override
  bool get hasLiveTraffic => false;

  @override
  Future<List<RoadRoute>> route(
    List<LatLng> waypoints, {
    bool alternatives = false,
  }) async {
    if (waypoints.length < 2) return const [];
    final coords = waypoints
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final alt = alternatives && waypoints.length == 2;
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/$coords'
      '?overview=full&geometries=geojson&alternatives=${alt ? 3 : false}',
    );
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('OSRM ${res.statusCode}');
    }
    return parseOsrm(res.body, trafficFactor: estimatedTrafficFactor(_now()));
  }

  /// Visible for tests.
  static List<RoadRoute> parseOsrm(String body, {double trafficFactor = 0}) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') throw Exception('OSRM ${json['code']}');
    return [
      for (final r in json['routes'] as List)
        () {
          final coords = (r['geometry']['coordinates'] as List)
              .map(
                (c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              )
              .toList();
          final free = (r['duration'] as num).toDouble();
          final names = <String>{
            for (final leg in r['legs'] as List)
              if ((leg['summary'] as String? ?? '').isNotEmpty)
                ...(leg['summary'] as String).split(', '),
          };
          return RoadRoute(
            points: coords,
            meters: (r['distance'] as num).toDouble(),
            freeFlowSeconds: free,
            trafficSeconds: free * trafficFactor,
            liveTraffic: false,
            summary: names.take(2).join(', '),
          );
        }(),
    ];
  }
}

/// TomTom Routing API with live traffic (free tier: 2,500 requests a day).
/// Get a key at developer.tomtom.com and put it in .env as TOMTOM_API_KEY.
class TomTomRouter extends RoadRouter {
  TomTomRouter(this.apiKey, {this.fallback, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;

  /// Used when TomTom fails (quota, network) so the collector still gets a route.
  final RoadRouter? fallback;
  final http.Client _client;

  @override
  bool get hasLiveTraffic => true;

  @override
  Future<List<RoadRoute>> route(
    List<LatLng> waypoints, {
    bool alternatives = false,
  }) async {
    if (waypoints.length < 2) return const [];
    try {
      final locs = waypoints
          .map((p) => '${p.latitude},${p.longitude}')
          .join(':');
      final alt = alternatives && waypoints.length == 2;
      final uri = Uri.https(
        'api.tomtom.com',
        '/routing/1/calculateRoute/$locs/json',
        {
          'key': apiKey,
          'traffic': 'true',
          'travelMode': 'car',
          'routeType': 'fastest',
          'computeTravelTimeFor': 'all',
          if (alt) 'maxAlternatives': '2',
        },
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('TomTom ${res.statusCode}');
      return parseTomTom(res.body);
    } catch (_) {
      if (fallback == null) rethrow;
      return fallback!.route(waypoints, alternatives: alternatives);
    }
  }

  /// Visible for tests.
  static List<RoadRoute> parseTomTom(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final r in json['routes'] as List)
        () {
          final s = r['summary'] as Map<String, dynamic>;
          final total = (s['travelTimeInSeconds'] as num).toDouble();
          final delay = (s['trafficDelayInSeconds'] as num? ?? 0).toDouble();
          return RoadRoute(
            points: [
              for (final leg in r['legs'] as List)
                for (final p in leg['points'] as List)
                  LatLng(
                    (p['latitude'] as num).toDouble(),
                    (p['longitude'] as num).toDouble(),
                  ),
            ],
            meters: (s['lengthInMeters'] as num).toDouble(),
            freeFlowSeconds: total - delay,
            trafficSeconds: delay,
            liveTraffic: true,
          );
        }(),
    ];
  }
}

/// The road to recommend: the fastest once traffic is counted. When that is
/// not also the shortest, the screen tells the collector it avoids traffic.
class RouteChoice {
  RouteChoice(List<RoadRoute> options)
    : options = [...options]..sort((a, b) => a.seconds.compareTo(b.seconds));

  /// Fastest first.
  final List<RoadRoute> options;

  RoadRoute get best => options.first;

  RoadRoute get shortest =>
      options.reduce((a, b) => a.meters <= b.meters ? a : b);

  /// Minutes saved by taking [best] instead of the shortest road.
  int get minutesSavedVsShortest =>
      ((shortest.seconds - best.seconds) / 60).round();

  bool get avoidsTraffic =>
      !identical(best, shortest) && minutesSavedVsShortest >= 1;
}
