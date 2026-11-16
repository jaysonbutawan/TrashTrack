import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/models/post.dart';
import 'package:hitchmeup/road_routing.dart';
import 'package:hitchmeup/route_planner.dart';
import 'package:hitchmeup/screens/collector/navigation_screen.dart';
import 'package:hitchmeup/theme.dart';
import 'package:hitchmeup/widgets/tagum_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/mock_backend.dart';

/// Start, a left turn ~550 m north, then the stop ~550 m west of the turn.
const _start = LatLng(7.4400, 125.8000);
const _turn = LatLng(7.4450, 125.8000);

class _FakeRouter extends RoadRouter {
  int calls = 0;
  final from = <LatLng>[];

  @override
  bool get hasLiveTraffic => false;

  @override
  Future<List<RoadRoute>> route(
    List<LatLng> waypoints, {
    bool alternatives = false,
  }) async {
    calls++;
    from.add(waypoints.first);
    final stop = waypoints.last;
    return [
      RoadRoute(
        points: [waypoints.first, _turn, stop],
        meters: 1100,
        freeFlowSeconds: 240,
        trafficSeconds: 0,
        liveTraffic: false,
        steps: [
          NavStep(
            point: waypoints.first,
            instruction: 'Start',
            maneuver: 'depart',
          ),
          const NavStep(
            point: _turn,
            instruction: 'Turn left onto Rizal Street',
            maneuver: 'turn',
          ),
          NavStep(
            point: stop,
            instruction: 'Arrive at stop 1',
            maneuver: 'arrive',
            stop: 0,
          ),
        ],
      ),
    ];
  }
}

class _FakeSpeaker implements Speaker {
  final said = <String>[];
  @override
  Future<void> say(String text) async => said.add(text);
  @override
  Future<void> stop() async {}
}

void main() {
  group('turn-by-turn steps from providers', () {
    test('OSRM steps become spoken instructions', () {
      final body = jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'distance': 900.0,
            'duration': 200.0,
            'geometry': {
              'coordinates': [
                [125.80, 7.44],
                [125.80, 7.445],
              ],
            },
            'legs': [
              {
                'summary': 'Rizal Street',
                'steps': [
                  {
                    'name': 'Apokon Road',
                    'distance': 500.0,
                    'maneuver': {
                      'type': 'depart',
                      'location': [125.80, 7.44],
                    },
                  },
                  {
                    'name': 'Rizal Street',
                    'distance': 400.0,
                    'maneuver': {
                      'type': 'turn',
                      'modifier': 'left',
                      'location': [125.80, 7.445],
                    },
                  },
                  {
                    'name': '',
                    'distance': 0.0,
                    'maneuver': {
                      'type': 'roundabout',
                      'exit': 2,
                      'location': [125.79, 7.445],
                    },
                  },
                  {
                    'name': '',
                    'distance': 0.0,
                    'maneuver': {
                      'type': 'arrive',
                      'location': [125.79, 7.446],
                    },
                  },
                ],
              },
            ],
          },
        ],
      });
      final steps = OsrmRouter.parseOsrm(body).single.steps;
      expect(steps.map((s) => s.instruction), [
        'Start on Apokon Road',
        'Turn left onto Rizal Street',
        'At the roundabout, take exit 2',
        'Arrive at stop 1',
      ]);
      expect(steps[1].point, const LatLng(7.445, 125.80));
      expect(steps.last.isArrival, isTrue);
      expect(steps.last.stop, 0);
    });

    test('TomTom guidance becomes steps with distances', () {
      final body = jsonEncode({
        'routes': [
          {
            'summary': {
              'lengthInMeters': 900,
              'travelTimeInSeconds': 200,
              'trafficDelayInSeconds': 0,
            },
            'legs': [
              {
                'points': [
                  {'latitude': 7.44, 'longitude': 125.80},
                ],
              },
            ],
            'guidance': {
              'instructions': [
                {
                  'routeOffsetInMeters': 0,
                  'point': {'latitude': 7.44, 'longitude': 125.80},
                  'instructionType': 'LOCATION_DEPARTURE',
                  'maneuver': 'DEPART',
                  'message': 'Leave from Apokon Road',
                },
                {
                  'routeOffsetInMeters': 500,
                  'point': {'latitude': 7.445, 'longitude': 125.80},
                  'instructionType': 'TURN',
                  'maneuver': 'TURN_LEFT',
                  'message': 'Turn left onto Rizal Street',
                },
                {
                  'routeOffsetInMeters': 900,
                  'point': {'latitude': 7.446, 'longitude': 125.79},
                  'instructionType': 'LOCATION_ARRIVAL',
                  'maneuver': 'ARRIVE',
                  'message': 'You have arrived',
                },
              ],
            },
          },
        ],
      });
      final steps = TomTomRouter.parseTomTom(body).single.steps;
      expect(steps[1].instruction, 'Turn left onto Rizal Street');
      expect(steps[1].meters, 400);
      expect(steps.last.instruction, 'Arrive at stop 1');
      expect(steps.last.stop, 0);
    });

    test('distance to the road and left to drive', () {
      const path = [_start, _turn];
      // ~110 m east of the line.
      const beside = LatLng(7.4425, 125.801);
      expect(metersToPath(beside, path), closeTo(110, 5));
      expect(metersLeftOnPath(_start, path), closeTo(553, 5));
      expect(metersLeftOnPath(_turn, path), closeTo(0, 1));
    });
  });

  testWidgets('navigates, speaks turns, re-routes and arrives', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed') &&
          details.toString().contains('attribution_layer')) {
        return;
      }
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final store = MockStore();
    MockAuthRepository(store).signInAs(UserRole.collector);
    final user = store.currentUser!;
    final stop = store.posts.firstWhere(
      (p) => p.status == PostStatus.reserved && p.reservedBy == user.id,
    );
    final gps = StreamController<GpsFix>();
    addTearDown(gps.close);
    final router = _FakeRouter();
    final speaker = _FakeSpeaker();

    await tester.pumpWidget(
      Provider<PostRepository>.value(
        value: MockPostRepository(store),
        child: MaterialApp(
          theme: buildTheme(),
          home: Provider<AppUser>.value(
            value: user,
            child: NavigationScreen(
              stops: [stop],
              track: () => gps.stream,
              router: router,
              speaker: speaker,
              keepAwake: false,
              rerouteEvery: Duration.zero,
            ),
          ),
        ),
      ),
    );
    Future<void> at(LatLng p) async {
      gps.add(GpsFix(p, 5));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    expect(find.text('Finding your location…'), findsOneWidget);
    await at(_start);
    expect(router.calls, 1);
    // The "Start" step is skipped: the next turn is shown.
    expect(find.text('Turn left onto Rizal Street'), findsOneWidget);
    expect(find.text('Open in Google Maps'), findsOneWidget);

    // Within ~100 m of the turn: spoken ahead of time.
    await at(const LatLng(7.4442, 125.8000));
    expect(
      speaker.said.where((s) => s.contains('Turn left onto Rizal Street')),
      isNotEmpty,
    );

    // Off the road twice → re-route from where the rider is.
    const lost = LatLng(7.4442, 125.8010);
    await at(lost);
    await at(lost);
    expect(router.calls, 2);
    expect(router.from.last, lost);
    expect(speaker.said, contains('Rerouting'));

    // At the stop: arrival sheet, then Collected.
    await at(stop.location);
    expect(find.text("You've arrived at stop 1"), findsOneWidget);
    expect(speaker.said.last, contains('You have arrived at stop 1'));
    await tester.tap(find.text('Collected · Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      store.posts.firstWhere((p) => p.id == stop.id).status,
      PostStatus.collected,
    );
    expect(find.text('All stops done'), findsOneWidget);
  });
}
