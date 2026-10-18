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

  // Brand + developer attribution.
  // Single source of truth: the splash, the EULA footer and the profile
  // signature block all render from these, so a rename or a new support
  // contact is a one-line change here and nowhere else.
  static const String appName = 'TeachCross';
  static const String brandName = 'CRIMSON';
  static const String developerName = 'Noah Timothy Keba Joseph';

  /// The collaboration lockup shown on the splash and in the signature block.
  static const String signatureLine = 'CRIMSON X NOAH TIMOTHY KEBA';

  // Support placeholders — replace with the live desk before shipping.
  static const String supportEmail = 'support@teachcross.app';
  static const String supportPhone = '+91 90000 00000';
}
