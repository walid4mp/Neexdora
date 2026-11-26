class AppSecrets {
  AppSecrets._();

  // ── Supabase ──
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  // ── Cloudinary ──
  static const String cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
  );

  static const String cloudinaryUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
  );

  // ── ZegoCloud ──
  static const int zegoAppId = int.fromEnvironment(
    'ZEGO_APP_ID',
    defaultValue: 0,
  );

  // ── FCM ──
  static const String fcmProjectId = String.fromEnvironment('FCM_PROJECT_ID');

  // ── Giphy (Comments → GIF picker) ──
  static const String giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');

  /// Names (never values) of the build-time settings that are missing.
  /// `assert` is stripped from release/web builds, so this runtime check is
  /// what actually stops the app from sending Supabase requests WITHOUT an
  /// `apikey` header (the 401 "No API key found in request" failure).
  static List<String> get missingKeys => <String>[
    if (supabaseUrl.trim().isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.trim().isEmpty) 'SUPABASE_ANON_KEY',
  ];

  static bool get isConfigured =>
      missingKeys.isEmpty && Uri.tryParse(supabaseUrl)?.hasScheme == true;

  /// Throws in EVERY build mode when Supabase settings were not compiled in.
  static void requireConfigured() {
    if (!isConfigured) {
      throw StateError(
        'Missing build-time configuration: ${missingKeys.join(', ')}. '
        'Build with --dart-define-from-file (see SETUP_NEW_SERVICES_AR.md).',
      );
    }
  }

  static void assertSecretsLoaded() {
    assert(
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
      '\n\n❌ AppSecrets are not loaded!\n'
      'Please run the app using this command:\n'
      '  flutter run --dart-define-from-file=.env\n'
      'Or configure your launch.json file (check .vscode/launch.json).\n',
    );
  }
}
