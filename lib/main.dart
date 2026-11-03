import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/app_user.dart';
import 'screens/auth/login_screen.dart';
import 'screens/collector/collector_home.dart';
import 'screens/household/household_home.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/post_service.dart';
import 'services/route_service.dart';
import 'theme.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final notifications = NotificationService();
  // Show route alerts that arrive while the app is open.
  notifications.foregroundMessages.listen((m) {
    final n = m.notification;
    if (n == null) return;
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text('${n.title ?? ''}\n${n.body ?? ''}',
          style: const TextStyle(fontSize: 17)),
      duration: const Duration(seconds: 8),
    ));
  });

  runApp(MultiProvider(
    providers: [
      Provider(create: (_) => AuthService()),
      Provider(create: (_) => PostService()),
      Provider(create: (_) => RouteService()),
      Provider.value(value: notifications),
    ],
    child: const BoteBakalApp(),
  ));
}

class BoteBakalApp extends StatelessWidget {
  const BoteBakalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bote-Bakal Tagum',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const AuthGate(),
    );
  }
}

/// Signed out → login. Signed in → household or collector home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: auth.authChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return StreamBuilder<AppUser?>(
          key: ValueKey(user.uid),
          stream: auth.profile(user.uid),
          builder: (context, p) {
            final profile = p.data;
            // Profile doc may lag a moment behind account creation.
            if (profile == null) return const _Loading();
            return Provider<AppUser>.value(
              value: profile,
              child: profile.isCollector
                  ? const CollectorHome()
                  : const HouseholdHome(),
            );
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
