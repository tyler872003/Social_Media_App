class AgoraConfig {
  // Prefer passing secrets with --dart-define in production.
  static const String appId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '5d34f05a782c4ee8a1d9bd018df15977',
  );

  static const String token = String.fromEnvironment(
    'AGORA_TEMP_TOKEN',
    defaultValue: '',
  );

  // Flip to true only once you've set up a real per-channel token server.
  static const bool useTokenAuth = false;

  static bool get isConfigured => appId.trim().isNotEmpty;
}
