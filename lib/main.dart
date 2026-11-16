import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'barangay_locator.dart';
import 'config.dart';
import 'data/noop_push.dart';
import 'data/repositories.dart';
import 'data/supabase/supabase_backend.dart';
import 'models/app_user.dart';
import 'road_routing.dart';
import 'screens/auth/finish_signup_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/collector/collector_home.dart';
import 'screens/household/household_home.dart';
import 'screens/auth/setup_needed_screen.dart';
import 'theme.dart';
import 'widgets/brand_splash.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await AppConfig.load();
  RoadRouter.instance = RoadRouter.fromKey(config.tomTomApiKey);
  BarangayLocator.instance = NominatimBarangayLocator();
  if (!config.hasSupabase) {
    runApp(const SetupNeededApp());
    return;
  }
  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabaseKey,
  );
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthRepository>.value(
          value: SupabaseAuthRepository(
            googleWebClientId: config.googleWebClientId,
            cache: prefs,
          ),
        ),
        Provider<PostRepository>.value(value: SupabasePostRepository()),
        Provider<RouteRepository>.value(value: SupabaseRouteRepository()),
        Provider<PushService>.value(value: NoopPushService()),
      ],
      child: const BoteBakalApp(),
    ),
  );
}

class BoteBakalApp extends StatelessWidget {
  const BoteBakalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bote-Bakal Tagum',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scaffoldMessengerKey: rootMessenger,
      home: const AuthGate(),
    );
  }
}

/// Signed out → login. First Google login → save the chosen role.
/// Otherwise → household or collector home.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AppUser?> _user = context
      .read<AuthRepository>()
      .currentUser();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _user,
      builder: (context, snap) {
        final user = snap.data;
        final Widget screen;
        if (snap.connectionState == ConnectionState.waiting) {
          screen = const BrandSplash(key: ValueKey('splash'));
        } else if (user == null) {
          screen = const LoginScreen(key: ValueKey('login'));
        } else if (user.needsProfile) {
          screen = FinishSignUpScreen(
            key: ValueKey('finish-${user.id}'),
            user: user,
          );
        } else {
          screen = Provider<AppUser>.value(
            key: ValueKey('home-${user.id}'),
            value: user,
            child: user.isCollector
                ? const CollectorHome()
                : const HouseholdHome(),
          );
        }
        // Fade between login, loading and home instead of a hard cut.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: screen,
        );
      },
    );
  }
}

/// Shown when .env has no Supabase keys, instead of crashing.
class SetupNeededApp extends StatelessWidget {
  const SetupNeededApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const SetupNeededScreen(),
  );
}
