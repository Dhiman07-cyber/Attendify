/// Application runtime configuration loaded securely via --dart-define / --dart-define-from-file.
/// No secrets or credentials should ever be hardcoded directly into source files.
class AppConfig {
  /// Base API URL for AttendHub backend services.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Google OAuth Web/Server Client ID used for requesting backend ID tokens.
  /// Injected at compile/build time from environment; with safe production fallback.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: String.fromEnvironment(
      'GOOGLE_CLIENT_ID',
      defaultValue: '116527451867-n5nghihimlb6t326l6hgf13ch4ad83uh.apps.googleusercontent.com',
    ),
  );

  /// Whether Google authentication is configured for this build flavor.
  static bool get isGoogleAuthEnabled => googleServerClientId.isNotEmpty;
}
