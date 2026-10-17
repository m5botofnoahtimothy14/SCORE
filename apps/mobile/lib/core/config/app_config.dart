/// App configuration — reads from environment variables
/// NEVER hardcode credentials here
class AppConfig {
  // These are injected at build time via --dart-define
  // Run: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  // Validate required config at startup
  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw Exception(
        'SUPABASE_URL is not configured. '
        'Run with --dart-define=SUPABASE_URL=your_url',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      throw Exception(
        'SUPABASE_ANON_KEY is not configured. '
        'Run with --dart-define=SUPABASE_ANON_KEY=your_key',
      );
    }
  }

  // Edge function base URL
  static String get edgeFunctionsUrl => '$supabaseUrl/functions/v1';
  
  // Rate limit configuration
  static const int maxLoginAttempts = 5;
  static const int maxOtpAttempts = 5;
  static const int messagePaginationSize = 30;
  static const int announcementPaginationSize = 20;
}
