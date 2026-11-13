import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shown instead of the app when .env has no Supabase keys.
class SetupNeededScreen extends StatelessWidget {
  const SetupNeededScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 14.5);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.settings_suggest, size: 64, color: Brand.kraft),
            const SizedBox(height: 12),
            const Text(
              'Backend not connected',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your Supabase and Google keys to the .env file in the '
              'project folder, then fully restart the app (not hot reload).',
              style: TextStyle(fontSize: 17, color: Brand.inkSoft),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brand.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Brand.line),
              ),
              child: const Text(
                'SUPABASE_URL=https://xxxx.supabase.co\n'
                'SUPABASE_PUBLISHABLE_KEY=sb_publishable_…\n'
                'GOOGLE_WEB_CLIENT_ID=…apps.googleusercontent.com',
                style: mono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
