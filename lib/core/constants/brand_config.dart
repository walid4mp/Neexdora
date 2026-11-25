/// ─────────────────────────────────────────────────────────────
///  Brand configuration — the ONLY place to edit owner-specific
///  contact info, links and team details shown inside the app.
///  Leave a value empty ('') to hide that row in the About screen.
/// ─────────────────────────────────────────────────────────────
class BrandConfig {
  BrandConfig._();

  static const String appName = 'Nexora';

  // About screen — links
  static const String websiteUrl = 'https://www.tiktok.com/@whsto.official';
  static const String websiteLabel = 'tiktok.com/@whsto.official';
  static const String whatsappNumber = ''; // digits only, e.g. 9665XXXXXXXX
  static const String whatsappUrl =
      'https://wa.me/message/VT2BBC7YZ4LHP1'; // used when whatsappNumber is empty
  static const String supportEmail = ''; // add your support email here
  static const String linkedinUrl = '';
  static const String githubUrl = 'https://github.com/walid4mp';

  // About screen — team card
  static const String teamName = 'WHSTO';
  static const String teamRole = 'Walid Hachemi — Innovate • Create • Inspire';

  // Force-update / "download" page (override with --dart-define=STORE_URL=...)
  static const String downloadUrl =
      'https://github.com/walid4mp/Neexdora/releases';
}
