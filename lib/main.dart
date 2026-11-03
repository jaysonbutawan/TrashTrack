import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/mock/mock_backend.dart';
import 'data/repositories.dart';
import 'models/app_user.dart';
import 'screens/auth/login_screen.dart';
import 'screens/collector/collector_home.dart';
import 'screens/household/household_home.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Backend wiring ────────────────────────────────────────────────
  // Static demo data for now. To use Supabase, initialize it here and
  // replace these four with Supabase implementations of the same interfaces.
  final store = MockStore();
  final AuthRepository auth = MockAuthRepository(store);
  final PostRepository posts = MockPostRepository(store);
  final RouteRepository routes = MockRouteRepository(store);
  final PushService push = MockPushService();
  // ──────────────────────────────────────────────────────────────────

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: auth),
        Provider.value(value: posts),
        Provider.value(value: routes),
        Provider.value(value: push),
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
      home: const AuthGate(),
    );
  }
}

/// Signed out → login. Signed in → household or collector home.
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return Provider<AppUser>.value(
          value: user,
          child: user.isCollector
              ? CollectorHome(key: ValueKey(user.id))
              : HouseholdHome(key: ValueKey(user.id)),
        );
      },
    );
  }
}
