import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/noop_push.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/main.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:provider/provider.dart';

import 'support/mock_backend.dart';

/// Drives the collector screens on sample data at phone size. Any layout
/// overflow fails the test.
void main() {
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpCollector(WidgetTester tester) async {
    // flutter_map's attribution label overflows only with the square-glyph
    // test font; ignore that one third-party widget, fail on everything else.
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
    final auth = MockAuthRepository(store)..signInAs(UserRole.collector);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthRepository>.value(value: auth),
          Provider<PostRepository>.value(value: MockPostRepository(store)),
          Provider<RouteRepository>.value(value: MockRouteRepository(store)),
          Provider<PushService>.value(value: NoopPushService()),
        ],
        child: const BoteBakalApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets('map shows the busiest barangay and the full ranking', (
    tester,
  ) async {
    await pumpCollector(tester);
    expect(find.textContaining('Busiest:'), findsOneWidget);
    await tester.tap(find.textContaining('Busiest:'));
    await settle(tester);
    expect(find.text('Where the recyclables are'), findsOneWidget);
    expect(find.textContaining('Tap one to see it on the map'), findsOneWidget);
    expect(find.byIcon(Icons.map), findsWidgets);
  });

  testWidgets('reserved tab opens the route guide with ordered stops', (
    tester,
  ) async {
    await pumpCollector(tester);
    await tester.tap(find.text('Reserved'));
    await settle(tester);
    expect(find.text('Route Guide'), findsOneWidget);
    // The sample collector has two reserved pickups (p2 and p10).
    expect(find.textContaining('your 2 pickups'), findsOneWidget);

    await tester.tap(find.text('Route Guide'));
    await settle(tester);
    expect(find.text('NEXT STOP'), findsOneWidget);
    expect(find.text('shortest route'), findsOneWidget);
    expect(find.text('Start Navigation (All Stops)'), findsOneWidget);
    // No GPS in tests → the route still shows, starting from the center.
    expect(find.textContaining('starts from the city center'), findsOneWidget);

    // Let the GPS time limit run out: the notice turns into a Retry.
    await tester.pump(const Duration(seconds: 13));
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('NEXT STOP'), findsOneWidget);
  });

  testWidgets('routes tab suggests barangays and pre-ticks them', (
    tester,
  ) async {
    await pumpCollector(tester);
    await tester.tap(find.text('Routes'));
    await settle(tester);
    expect(find.text('SUGGESTED FOR YOUR NEXT ROUTE'), findsOneWidget);
    expect(find.text('Plan a Route for These 3'), findsOneWidget);

    await tester.tap(find.text('Plan a Route for These 3'));
    await settle(tester);
    expect(find.textContaining('(3 chosen)'), findsOneWidget);
    expect(find.textContaining('waiting'), findsWidgets);

    // Narrow the first ticked barangay down to two puroks.
    expect(find.text('Whole barangay'), findsWidgets);
    await tester.tap(find.text('Choose Purok').first);
    await settle(tester);
    expect(find.textContaining('Puroks in'), findsOneWidget);
    Finder chip(String n) =>
        find.descendant(of: find.byType(FilterChip), matching: find.text(n));
    await tester.tap(chip('1'));
    await tester.tap(chip('3'));
    await tester.pump();
    await tester.tap(find.text('Done (2 puroks)'));
    await settle(tester);
    expect(find.text('Purok 1, 3'), findsOneWidget);
  });
}
