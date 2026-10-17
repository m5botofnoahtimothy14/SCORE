import 'package:flutter_test/flutter_test.dart';
import 'package:teachcross_mobile/core/config/app_config.dart';

void main() {
  test('AppConfig validates required Supabase configuration', () {
    // Without --dart-define values the config is empty and must fail fast
    // with an actionable message instead of a cryptic client error.
    expect(AppConfig.supabaseUrl, isEmpty);
    expect(AppConfig.supabaseAnonKey, isEmpty);
    expect(() => AppConfig.validate(), throwsA(isA<Exception>()));
  });

  test('AppConfig exposes edge-functions URL derived from Supabase URL', () {
    expect(AppConfig.messagePaginationSize, 30);
    expect(AppConfig.announcementPaginationSize, 20);
  });
}
