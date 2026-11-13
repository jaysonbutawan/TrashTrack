import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Keys read from the `.env` file in the project root (see `.env.example`).
/// When the Supabase keys are blank the app shows a "Backend not connected"
/// screen.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseKey,
    required this.googleWebClientId,
  });

  final String supabaseUrl;

  /// Publishable key (`sb_publishable_…`) or the legacy anon key.
  final String supabaseKey;

  /// OAuth client ID of type **Web application** from Google Cloud — the same
  /// one entered in Supabase → Authentication → Providers → Google.
  final String googleWebClientId;

  bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  static Future<AppConfig> load() async {
    await dotenv.load(fileName: '.env', isOptional: true);
    String read(String key) => (dotenv.maybeGet(key) ?? '').trim();
    return AppConfig(
      supabaseUrl: read('SUPABASE_URL'),
      supabaseKey: read('SUPABASE_PUBLISHABLE_KEY').isNotEmpty
          ? read('SUPABASE_PUBLISHABLE_KEY')
          : read('SUPABASE_ANON_KEY'),
      googleWebClientId: read('GOOGLE_WEB_CLIENT_ID'),
    );
  }
}
