import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/noop_push.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/main.dart';
import 'package:hitchmeup/widgets/post_form_widgets.dart';
import 'package:provider/provider.dart';

import 'support/mock_backend.dart';

/// Drives the household screens on demo data at phone size. Any layout
/// overflow fails the test.
void main() {
  late MockAuthRepository auth;

  /// [as]: id of an existing account Google signs in as; null = new account.
  Future<void> pumpApp(
    WidgetTester tester, {
    String? as = 'u-household-1',
  }) async {
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
    auth = MockAuthRepository(store)..nextGoogleAccount = as;
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
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('new account: pick Collector, Google, straight to home', (
    tester,
  ) async {
    await pumpApp(tester, as: null);
    expect(find.text('Who are you?'), findsOneWidget);
    // Nothing happens until a role is picked.
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    expect(find.text('Who are you?'), findsOneWidget);
    await tester.tap(find.text('Collector'));
    await tester.pump();
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    await settle(tester);
    final me = await auth.currentUser().first;
    expect(me!.isCollector, isTrue);
    expect(me.needsProfile, isFalse);
    expect(find.text('Who are you?'), findsNothing);
  });

  testWidgets('household home: search, Past tab, filters', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Household'));
    await tester.pump();
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);

    expect(find.textContaining('Maria'), findsWidgets);
    expect(find.text('Active'), findsOneWidget);
    // Active posts of the demo household: p1 (available) and p2 (reserved).
    expect(find.text('Edit'), findsOneWidget);
    expect(find.textContaining('is coming'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'bakal');
    await settle(tester);
    expect(find.text('Edit'), findsNothing); // only the metal post is left
    await tester.enterText(find.byType(TextField).first, '');
    await settle(tester);

    await tester.tap(find.text('Past'));
    await settle(tester);
    expect(find.textContaining('Rate '), findsWidgets); // p3 not yet rated

    await tester.tap(find.byTooltip('Filter'));
    await settle(tester);
    expect(find.text('Filter & sort'), findsOneWidget);
    await tester.tap(find.text('Heaviest first'));
    await tester.tap(find.text('Show Results'));
    await settle(tester);
    expect(find.text('ALL PICKUPS'), findsOneWidget);
  });

  testWidgets('post form: type tiles, kg stepper, barangay sheet', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Household'));
    await tester.pump();
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    await tester.tap(find.text('Post Recyclables'));
    await settle(tester);

    expect(find.text('Plastic'), findsOneWidget);
    await tester.tap(find.text('Plastic'));
    await tester.pump();
    expect(find.text('2 of 6 done'), findsOneWidget); // weight + type

    await tester.scrollUntilVisible(
      find.text('+5 kg'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(WeightStepper), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.tap(find.text('+5 kg'));
    await tester.pump();
    expect(find.text('7'), findsOneWidget); // 1 + 0.5 + 0.5 + 5

    await tester.scrollUntilVisible(
      find.text('Choose barangay'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Magugpo Poblacion').first);
    await tester.pump();
    await tester.tap(find.text('Magugpo Poblacion').first); // followed chip
    await tester.pump();
    // Barangay alone is not enough: the purok is part of the step.
    expect(find.text('2 of 6 done'), findsOneWidget);
    await tester.ensureVisible(find.text('Choose purok'));
    await tester.pump();
    await tester.tap(find.text('Choose purok'));
    await settle(tester);
    expect(find.text('Purok in Magugpo Poblacion'), findsOneWidget);
    await tester.tap(find.text('Purok 3'));
    await settle(tester);
    expect(find.text('3 of 6 done'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.search).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.search).first);
    await settle(tester);
    expect(find.text('Which barangay?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'apo');
    await tester.pump();
    await tester.tap(find.text('Apokon'));
    await settle(tester);
    expect(find.text('Apokon'), findsOneWidget);
    // A purok of the old barangay does not carry over.
    expect(find.text('Purok 3'), findsNothing);
    expect(find.text('Choose purok'), findsOneWidget);
  });
}
