/// ─────────────────────────────────────────────────────────────
///  Brand configuration — the ONLY place to edit owner-specific
///  contact info, links and team details shown inside the app.
///  Leave a value empty ('') to hide that row in the About screen.
/// ─────────────────────────────────────────────────────────────
class BrandConfig {
  BrandConfig._();

  static const String appName = 'Nexora';

  // About screen — links
  static const String websiteUrl = 'https://nexora.example.com';
  static const String websiteLabel = 'nexora.example.com';
  static const String whatsappNumber = ''; // digits only, e.g. 9665XXXXXXXX
  static const String supportEmail = 'support@nexora.example.com';
  static const String linkedinUrl = '';
  static const String githubUrl = '';

  // About screen — team card
  static const String teamName = 'Nexora Team';
  static const String teamRole = 'Product & Engineering';

  // Force-update / "download" page (override with --dart-define=STORE_URL=...)
  static const String downloadUrl = 'https://nexora.example.com/download';
}
