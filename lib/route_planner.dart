// Route suggestions for collectors. Pure Dart (no Flutter), so it is easy to
// test: shortest visiting order for a set of pickups, and which barangays
// have the most recyclables waiting.

import 'package:latlong2/latlong.dart';

import 'models/post.dart';
import 'models/route_schedule.dart';

const _distance = Distance();

/// Straight-line distance in meters.
double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

/// Roads are longer than a straight line; this is a typical city factor.
const double roadFactor = 1.3;

/// Average speed of a tricycle / kariton collector in town, with stops.
const double _kmPerHour = 18;

/// Minutes spent at each house (weighing and loading).
const int minutesPerStop = 6;

class PlannedRoute {
  const PlannedRoute({
    required this.start,
    required this.stops,
    required this.legMeters,
  });

  final LatLng start;

  /// Pickups in the suggested visiting order.
  final List<RecyclablePost> stops;

  /// Estimated road distance to each stop from the previous point.
  final List<double> legMeters;

  double get totalMeters => legMeters.fold(0, (a, b) => a + b);
  double get totalKg => stops.fold(0, (a, p) => a + p.weightKg);

  /// Travel time plus time at each stop.
  int get totalMinutes =>
      (totalMeters / 1000 / _kmPerHour * 60).round() +
      stops.length * minutesPerStop;

  List<LatLng> get path => [start, for (final s in stops) s.location];
}

String formatDistance(double meters) => meters < 950
    ? '${(meters / 50).round() * 50} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

/// Shortest order to visit every stop, starting at [start] (the collector does
/// not need to come back). Exact for up to 8 stops; for more, a
/// nearest-neighbour route improved with 2-opt, which is very close to best.
PlannedRoute planRoute(LatLng start, List<RecyclablePost> stops) {
  if (stops.isEmpty) {
    return PlannedRoute(start: start, stops: const [], legMeters: const []);
  }
  final pts = [start, for (final s in stops) s.location];
  final n = pts.length;
  final d = List.generate(
    n,
    (i) =>
        List.generate(n, (j) => i == j ? 0.0 : metersBetween(pts[i], pts[j])),
  );

  double length(List<int> order) {
    var sum = 0.0, at = 0;
    for (final i in order) {
      sum += d[at][i];
      at = i;
    }
    return sum;
  }

  List<int> best;
  if (stops.length <= 8) {
    // Try every order (at most 8! = 40,320).
    best = [];
    var bestLen = double.infinity;
    final order = <int>[];
    final used = List.filled(n, false);
    void search(int at, double soFar) {
      if (soFar >= bestLen) return;
      if (order.length == n - 1) {
        bestLen = soFar;
        best = [...order];
        return;
      }
      for (var i = 1; i < n; i++) {
        if (used[i]) continue;
        used[i] = true;
        order.add(i);
        search(i, soFar + d[at][i]);
        order.removeLast();
        used[i] = false;
      }
    }

    search(0, 0);
  } else {
    // Nearest neighbour…
    best = [];
    final left = {for (var i = 1; i < n; i++) i};
    var at = 0;
    while (left.isNotEmpty) {
      final next = left.reduce((a, b) => d[at][a] <= d[at][b] ? a : b);
      best.add(next);
      left.remove(next);
      at = next;
    }
    // …then 2-opt: keep reversing a stretch while that makes it shorter.
    var improved = true;
    while (improved) {
      improved = false;
      for (var i = 0; i < best.length - 1; i++) {
        for (var j = i + 1; j < best.length; j++) {
          final candidate = [
            ...best.sublist(0, i),
            ...best.sublist(i, j + 1).reversed,
            ...best.sublist(j + 1),
          ];
          if (length(candidate) + 0.5 < length(best)) {
            best = candidate;
            improved = true;
          }
        }
      }
    }
  }

  final legs = <double>[];
  var at = 0;
  for (final i in best) {
    legs.add(d[at][i] * roadFactor);
    at = i;
  }
  return PlannedRoute(
    start: start,
    stops: [for (final i in best) stops[i - 1]],
    legMeters: legs,
  );
}

/// How much is waiting in one barangay.
class BarangayDemand {
  const BarangayDemand({
    required this.barangay,
    required this.posts,
    required this.totalKg,
    required this.forSale,
    required this.center,
    required this.nextRoute,
  });

  final String barangay;

  /// Posts still available (not reserved).
  final int posts;
  final double totalKg;
  final int forSale;

  /// Middle of the posts, for moving the map there.
  final LatLng center;

  /// Soonest upcoming route (by any collector) that covers this barangay.
  final RouteSchedule? nextRoute;

  int get free => posts - forSale;

  /// Nobody has scheduled a visit yet — the best place for a new route.
  bool get unserved => nextRoute == null;
}

/// Barangays with available posts, busiest first (most posts, then most kg).
List<BarangayDemand> rankBarangays(
  List<RecyclablePost> available,
  List<RouteSchedule> upcomingRoutes,
) {
  final groups = <String, List<RecyclablePost>>{};
  for (final p in available) {
    if (p.status == PostStatus.available) {
      groups.putIfAbsent(p.barangay, () => []).add(p);
    }
  }
  final routes = [...upcomingRoutes]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final list = [
    for (final e in groups.entries)
      BarangayDemand(
        barangay: e.key,
        posts: e.value.length,
        totalKg: e.value.fold(0, (a, p) => a + p.weightKg),
        forSale: e.value.where((p) => p.label == PostLabel.forSale).length,
        center: LatLng(
          e.value.fold(0.0, (a, p) => a + p.location.latitude) / e.value.length,
          e.value.fold(0.0, (a, p) => a + p.location.longitude) /
              e.value.length,
        ),
        nextRoute: routes.where((r) => r.barangays.contains(e.key)).firstOrNull,
      ),
  ];
  list.sort((a, b) {
    final byPosts = b.posts.compareTo(a.posts);
    return byPosts != 0 ? byPosts : b.totalKg.compareTo(a.totalKg);
  });
  return list;
}

/// Best barangays for a collector's next route: busy ones, with a barangay
/// nobody has scheduled yet counting double (same supply, no competition).
List<BarangayDemand> suggestBarangays(
  List<BarangayDemand> ranking, {
  int count = 3,
}) {
  int score(BarangayDemand d) => d.posts * (d.unserved ? 2 : 1);
  final list = [...ranking]
    ..sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      return byScore != 0 ? byScore : b.totalKg.compareTo(a.totalKg);
    });
  return list.take(count).toList();
}
