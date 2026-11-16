import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/road_routing.dart';
import 'package:hitchmeup/screens/collector/route_guide_screen.dart';
import 'package:latlong2/latlong.dart';

import 'route_planner_test.dart' show post;

RoadRoute road(double meters, double free, double traffic) => RoadRoute(
  points: const [LatLng(7.4, 125.8), LatLng(7.41, 125.8)],
  meters: meters,
  freeFlowSeconds: free,
  trafficSeconds: traffic,
  liveTraffic: true,
);

void main() {
  test('OSRM response becomes road routes with estimated traffic', () {
    final body = jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 2500.0,
          'duration': 300.0,
          'geometry': {
            'coordinates': [
              [125.80, 7.44],
              [125.81, 7.45],
            ],
          },
          'legs': [
            {'summary': 'Apokon Road, National Highway'},
          ],
        },
      ],
    });
    final routes = OsrmRouter.parseOsrm(body, trafficFactor: 0.4);
    expect(routes, hasLength(1));
    final r = routes.single;
    expect(r.points.first, const LatLng(7.44, 125.80));
    expect(r.meters, 2500);
    expect(r.seconds, 420); // 300 s + 40 % rush hour
    expect(r.liveTraffic, isFalse);
    expect(r.traffic, TrafficLevel.heavy);
    expect(r.summary, 'Apokon Road, National Highway');
  });

  test('TomTom response carries live traffic delay', () {
    final body = jsonEncode({
      'routes': [
        {
          'summary': {
            'lengthInMeters': 3000,
            'travelTimeInSeconds': 600,
            'trafficDelayInSeconds': 120,
          },
          'legs': [
            {
              'points': [
                {'latitude': 7.44, 'longitude': 125.80},
                {'latitude': 7.45, 'longitude': 125.81},
              ],
            },
          ],
        },
      ],
    });
    final r = TomTomRouter.parseTomTom(body).single;
    expect(r.liveTraffic, isTrue);
    expect(r.freeFlowSeconds, 480);
    expect(r.trafficSeconds, 120);
    expect(r.minutes, 10);
    expect(r.traffic, TrafficLevel.moderate);
  });

  test('suggests the faster road when the shortest one is jammed', () {
    final shortJammed = road(2000, 300, 600); // 15 min
    final longClear = road(2800, 400, 20); // 7 min
    final choice = RouteChoice([shortJammed, longClear]);
    expect(choice.best, same(longClear));
    expect(choice.shortest, same(shortJammed));
    expect(choice.avoidsTraffic, isTrue);
    expect(choice.minutesSavedVsShortest, 8);

    final clear = RouteChoice([road(2000, 300, 0), road(2800, 400, 0)]);
    expect(clear.avoidsTraffic, isFalse);
  });

  test('rush hours are estimated busier than late evening', () {
    final monday8am = DateTime(2026, 11, 16, 7, 45);
    final monday10pm = DateTime(2026, 11, 16, 22);
    expect(
      estimatedTrafficFactor(monday8am),
      greaterThan(estimatedTrafficFactor(monday10pm)),
    );
    expect(estimatedTrafficFactor(monday10pm), 0);
  });

  test('straight-line fallback works offline', () async {
    final r = (await const StraightLineRouter().route(const [
      LatLng(7.40, 125.80),
      LatLng(7.41, 125.80),
    ])).single;
    expect(r.meters, greaterThan(1100)); // ~1.1 km × road factor
  });

  test('suggested route takes the nearest available posts', () {
    final picked = nearestAvailable(
      [
        post('far', 7.50, 125.80),
        post('near', 7.401, 125.80),
        post('mid', 7.42, 125.80),
      ],
      const LatLng(7.40, 125.80),
      2,
    );
    expect(picked.map((p) => p.id), ['near', 'mid']);
  });
}
