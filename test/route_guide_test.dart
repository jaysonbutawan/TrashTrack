import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/models/post.dart';
import 'package:hitchmeup/road_routing.dart';
import 'package:hitchmeup/screens/collector/route_guide_screen.dart';
import 'package:hitchmeup/theme.dart';
import 'package:hitchmeup/widgets/tagum_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/mock_backend.dart';

/// Two roads: the short one is jammed, the longer one is clear.
class _JammedRouter extends RoadRouter {
  @override
  bool get hasLiveTraffic => true;

  @override
  Future<List<RoadRoute>> route(
    List<LatLng> waypoints, {
    bool alternatives = false,
  }) async => [
    RoadRoute(
      points: waypoints,
      meters: 2000,
      freeFlowSeconds: 300,
      trafficSeconds: 600,
      liveTraffic: true,
      summary: 'National Highway',
    ),
    if (alternatives)
      RoadRoute(
        points: waypoints,
        meters: 2800,
        freeFlowSeconds: 400,
        trafficSeconds: 20,
        liveTraffic: true,
        summary: 'Apokon Road',
      ),
  ];
}

void main() {
  late MockStore store;
  late AppUser collector;

  Future<(LatLng?, String?)> noGps() async => (null, 'Location is off.');

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpGuide(
    WidgetTester tester, {
    RecyclablePost? target,
    Stream<GpsFix> Function()? track,
  }) async {
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
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostRepository>.value(value: MockPostRepository(store)),
          Provider<AppUser>.value(value: collector),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: RouteGuideScreen(
            target: target,
            locate: noGps,
            track: track ?? () => const Stream.empty(),
            router: _JammedRouter(),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  setUp(() {
    store = MockStore();
    MockAuthRepository(store).signInAs(UserRole.collector);
    collector = store.currentUser!;
  });

  testWidgets('view route to a post without reserving it, avoiding traffic', (
    tester,
  ) async {
    final target = store.posts.firstWhere(
      (p) => p.status == PostStatus.available,
    );
    await pumpGuide(tester, target: target);

    expect(find.text('Route to Pickup'), findsOneWidget);
    expect(find.text('NEXT STOP'), findsOneWidget);
    expect(find.text('Start Navigation'), findsOneWidget);
    expect(
      find.textContaining('avoids traffic and saves 8 min'),
      findsOneWidget,
    );
    expect(find.textContaining('Fastest now'), findsOneWidget);
    expect(find.textContaining('Shortest distance'), findsOneWidget);
    // Looking is not reserving.
    expect(find.text('Reserve'), findsOneWidget);
    expect(
      store.posts.firstWhere((p) => p.id == target.id).status,
      PostStatus.available,
    );
  });

  testWidgets('no reservations: suggests the shortest route nearby', (
    tester,
  ) async {
    store.posts.removeWhere(
      (p) => p.status == PostStatus.reserved && p.reservedBy == collector.id,
    );
    await pumpGuide(tester);

    expect(find.text('Suggested Route'), findsOneWidget);
    expect(find.textContaining('No reservations yet'), findsOneWidget);
    expect(find.text('NEXT STOP'), findsOneWidget);
    expect(find.text('Start Navigation (All Stops)'), findsOneWidget);
  });

  testWidgets('live GPS shows where the collector is right now', (
    tester,
  ) async {
    final gps = StreamController<GpsFix>();
    addTearDown(gps.close);
    await pumpGuide(tester, track: () => gps.stream);
    expect(find.textContaining('starts from the city center'), findsOneWidget);

    gps.add(const GpsFix(LatLng(7.4478, 125.8078), 8));
    await settle(tester);
    expect(find.text('LIVE ±8 m'), findsOneWidget);
    expect(find.text('from you'), findsOneWidget);
    expect(find.textContaining('starts from the city center'), findsNothing);
  });
}
