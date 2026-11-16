import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/noop_push.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/main.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/screens/collector/navigation_screen.dart';
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

  late MockStore store;

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
    store = MockStore();
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

    // Navigation happens inside the app; Google Maps is only a backup.
    expect(find.byTooltip('Open in Google Maps'), findsOneWidget);
    await tester.tap(find.text('Start Navigation (All Stops)'));
    await settle(tester);
    expect(find.byType(NavigationScreen), findsOneWidget);
    expect(find.textContaining('Stop 1 of 2'), findsOneWidget);
    await tester.tap(find.text('End'));
    await settle(tester);
    expect(find.byType(NavigationScreen), findsNothing);
  });

  testWidgets('collector cancels a reservation and says why', (tester) async {
    await pumpCollector(tester);
    await tester.tap(find.text('Reserved'));
    await settle(tester);
    expect(find.text('Cancel'), findsNWidgets(2)); // p2 and p10

    await tester.tap(find.text('Cancel').first);
    await settle(tester);
    expect(find.text('Cancel this pickup?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Cancel Reservation');
    // A reason is required.
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Price not agreed'));
    await tester.pump();
    await tester.tap(confirm);
    await settle(tester);

    expect(find.text('Cancel'), findsOneWidget); // one reservation left
    expect(find.textContaining('back on the map'), findsOneWidget);
  });

  testWidgets('collector deletes one of their routes', (tester) async {
    await pumpCollector(tester);
    await tester.tap(find.text('Routes'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byTooltip('Cancel route').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    int mine() =>
        store.routes.where((r) => r.collectorId == 'u-collector-1').length;
    final before = mine();
    final first = store.routes.firstWhere(
      (r) => r.collectorId == 'u-collector-1',
    );
    await tester.tap(find.byTooltip('Cancel route').first);
    await settle(tester);
    await tester.tap(find.text('Yes'));
    await settle(tester);
    expect(find.text('Route cancelled.'), findsOneWidget);
    expect(mine(), before - 1);
    expect(store.routes.any((r) => r.id == first.id), isFalse);
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
    // Whatever the barangay's list is, take its first two puroks.
    final chips = find.byType(FilterChip);
    String label(int i) => tester
        .widget<Text>(
          find.descendant(of: chips.at(i), matching: find.byType(Text)).first,
        )
        .data!;
    final first = label(0), second = label(1);
    await tester.tap(chips.at(0));
    await tester.tap(chips.at(1));
    await tester.pump();
    // Long lists (Visayan Village has 38) push the button below the fold.
    await tester.ensureVisible(find.text('Done (2 puroks)'));
    await tester.pump();
    await tester.tap(find.text('Done (2 puroks)'));
    await settle(tester);
    expect(find.textContaining('$first, $second'), findsOneWidget);
  });
}
