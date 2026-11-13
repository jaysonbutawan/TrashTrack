import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/noop_push.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/main.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/screens/household/create_post_screen.dart';
import 'package:hitchmeup/theme.dart';
import 'package:hitchmeup/widgets/tagum_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/mock_backend.dart';

/// A house in Magugpo Poblacion.
const _house = LatLng(7.4472, 125.8065);

void main() {
  late MockStore store;
  late MockAuthRepository auth;

  void phoneSize(WidgetTester tester) {
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
  }

  Widget providers(Widget child) => MultiProvider(
    providers: [
      Provider<AuthRepository>.value(value: auth),
      Provider<PostRepository>.value(value: MockPostRepository(store)),
      Provider<RouteRepository>.value(value: MockRouteRepository(store)),
      Provider<PushService>.value(value: NoopPushService()),
    ],
    child: child,
  );

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() {
    store = MockStore();
    auth = MockAuthRepository(store)..signInAs(UserRole.household);
  });

  testWidgets('post form finds the house and the pin can be dragged', (
    tester,
  ) async {
    phoneSize(tester);
    // Fake GPS: a rough reading first, then a precise one.
    Future<(GpsFix?, String?)> gps({void Function(GpsFix)? onProgress}) async {
      onProgress?.call(const GpsFix(LatLng(7.4475, 125.8070), 60));
      const best = GpsFix(_house, 6);
      onProgress?.call(best);
      return (best, null);
    }

    final user = await auth.currentUser().first;
    await tester.pumpWidget(
      providers(
        MaterialApp(
          theme: buildTheme(),
          home: Provider<AppUser>.value(
            value: user!,
            child: CreatePostScreen(locate: gps),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('Adjust Pin'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('accurate to ±6 m'), findsOneWidget);

    await tester.ensureVisible(find.text('Adjust Pin'));
    await tester.pump();
    await tester.tap(find.text('Adjust Pin'));
    await settle(tester);
    expect(
      find.text('Drag the map so the pin is on your gate'),
      findsOneWidget,
    );
    expect(find.text('Pin is at your location'), findsOneWidget);

    // Drag the map: the pin (always in the middle) lands somewhere else.
    await tester.drag(find.byType(FlutterMap), const Offset(-150, 0));
    await settle(tester);
    expect(find.textContaining('from you'), findsOneWidget);

    await tester.tap(find.text('Pickup Here'));
    await settle(tester);
    expect(find.text('Pin set. Collectors will go here.'), findsOneWidget);
  });

  testWidgets('without GPS the user can still set the pin by hand', (
    tester,
  ) async {
    phoneSize(tester);
    Future<(GpsFix?, String?)> noGps({
      void Function(GpsFix)? onProgress,
    }) async => (null, 'Please turn on Location (GPS).');

    final user = await auth.currentUser().first;
    await tester.pumpWidget(
      providers(
        MaterialApp(
          theme: buildTheme(),
          home: Provider<AppUser>.value(
            value: user!,
            child: CreatePostScreen(locate: noGps),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Set Pin'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Please turn on Location (GPS).'), findsOneWidget);
  });

  testWidgets('routes: home barangay is automatic, riders per barangay, '
      'add only new barangays', (tester) async {
    phoneSize(tester);
    // Real time: the mock waits a little before saving.
    await tester.runAsync(
      () => auth.updateProfile(barangay: 'Magugpo Poblacion'),
    );
    await tester.pumpWidget(providers(const BoteBakalApp()));
    await settle(tester);
    await tester.tap(find.text('Routes'));
    await settle(tester);

    expect(find.text('Riders Coming'), findsOneWidget);
    // Sample routes: Jun → Poblacion + North; Rodel → Visayan + Apokon.
    expect(find.text('Jun Dela Cruz'), findsOneWidget);
    expect(find.text('Rodel Ampit'), findsOneWidget);
    expect(find.textContaining('Also passing Magugpo North'), findsOneWidget);
    expect(find.textContaining('automatically'), findsOneWidget);

    await tester.tap(find.text('Add barangay'));
    await settle(tester);
    expect(find.text('Add a barangay'), findsOneWidget);
    // Already added → listed once on top as "Added", not pickable.
    expect(find.text('ALREADY ADDED'), findsOneWidget);
    expect(find.text('Added'), findsNWidgets(2));

    await tester.tap(find.text('Apokon'));
    await settle(tester);
    // Apokon now has its own section, with Rodel in it too ("also passing
    // Visayan Village" appears only on his card under Apokon).
    await tester.scrollUntilVisible(
      find.textContaining('Also passing Visayan Village'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Also passing Visayan Village'), findsOneWidget);
    expect(
      (await auth.currentUser().first)!.followedBarangays,
      contains('Apokon'),
    );
  });
}
