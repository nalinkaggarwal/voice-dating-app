/// Environment-specific config, resolved at build time via
/// `--dart-define`, never hardcoded. Keeps dev/staging/prod switching out
/// of source control (see .env.example for the values a build script
/// should pass through as --dart-define=API_BASE_URL=... etc).
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static bool get isProduction => environment == 'production';
}
