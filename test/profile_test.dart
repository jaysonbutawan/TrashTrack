import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitchmeup/data/noop_push.dart';
import 'package:hitchmeup/data/repositories.dart';
import 'package:hitchmeup/main.dart';
import 'package:hitchmeup/models/app_user.dart';
import 'package:hitchmeup/screens/common/profile_tab.dart';
import 'package:hitchmeup/theme.dart';
import 'package:hitchmeup/widgets/common.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/mock_backend.dart';
import 'support/mock_data.dart';

/// Profile tab for both roles, on demo data at phone size.
void main() {
  late MockStore store;
  late MockAuthRepository auth;

  void phoneSize(WidgetTester tester) {
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

  List<Provider> providers() => [
    Provider<AuthRepository>.value(value: auth),
    Provider<PostRepository>.value(value: MockPostRepository(store)),
    Provider<RouteRepository>.value(value: MockRouteRepository(store)),
    Provider<PushService>.value(value: NoopPushService()),
  ];

  Future<void> pumpApp(WidgetTester tester, UserRole role) async {
    phoneSize(tester);
    store = MockStore();
    auth = MockAuthRepository(store)
      ..nextGoogleAccount = mockAccounts[role]!.id;
    await tester.pumpWidget(
      MultiProvider(providers: providers(), child: const BoteBakalApp()),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.text(
        role == UserRole.collector ? "I'm a Collector" : "I'm a Household",
      ),
    );
    await settle(tester);
  }

  testWidgets('household: pick barangay, edit number, log out', (tester) async {
    await pumpApp(tester, UserRole.household);
    await tester.tap(find.text('Profile'));
    await settle(tester);

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Choose where you live'), findsOneWidget);
    await tester.tap(find.text('Choose'));
    await settle(tester);
    expect(find.text('Which barangay?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'apo');
    await tester.pump();
    await tester.tap(find.text('Apokon'));
    await settle(tester);
    expect(store.currentUser!.barangay, 'Apokon');
    expect(find.text('Choose where you live'), findsNothing);

    final hadPhone = store.currentUser!.phone.isNotEmpty;
    await tester.tap(find.text(hadPhone ? 'Edit' : 'Add'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), '0917 555 1234');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(store.currentUser!.phone, '0917 555 1234');
    rootMessenger.currentState!.clearSnackBars();
    await settle(tester);

    await tester.scrollUntilVisible(
      find.text('Log Out'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Log Out'));
    await settle(tester);
    await tester.tap(find.text('Log Out').last); // confirm dialog
    await settle(tester);
    expect(store.currentUser, isNull);
  });

  testWidgets('collector: change name and number', (tester) async {
    await pumpApp(tester, UserRole.collector);
    await tester.tap(find.text('Profile'));
    await settle(tester);

    expect(find.text('My Profile'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), 'Pedro Basura');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(store.currentUser!.name, 'Pedro Basura');

    final hadPhone = store.currentUser!.phone.isNotEmpty;
    await tester.tap(find.text(hadPhone ? 'Edit' : 'Add'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), '09981234567');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(store.currentUser!.phone, '09981234567');
  });

  testWidgets('collector: current location on the profile', (tester) async {
    phoneSize(tester);
    store = MockStore();
    auth = MockAuthRepository(store)..signInAs(UserRole.collector);
    final user = store.currentUser!;
    var calls = 0;
    Future<(LatLng?, String?)> fakeLocate() async {
      calls++;
      return calls == 1
          ? (null, 'Please turn on Location (GPS).')
          : (const LatLng(7.4478, 125.8078), null);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...providers(),
          Provider<AppUser>.value(value: user),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: ProfileTab(user: user, locate: fakeLocate),
        ),
      ),
    );
    final getLocation = find.text('Get My Current Location');
    await tester.scrollUntilVisible(
      getLocation,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(getLocation);
    await settle(tester);
    expect(find.text('Please turn on Location (GPS).'), findsOneWidget);

    await tester.tap(getLocation);
    await settle(tester);
    expect(find.text('7.44780, 125.80780'), findsOneWidget);
    expect(find.text('Update Location'), findsOneWidget);
    expect(find.text('Guide Me to My Pickups'), findsOneWidget);
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
