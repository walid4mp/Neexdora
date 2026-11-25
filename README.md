# Nexora

Real-time social platform built with Flutter + Supabase + Firebase.
Chat · Group & video calls · Stories · Reels · AI assistant · Stickers · 2FA · App lock · Offline-first · English/Arabic · 12 themes.

📘 **Full setup, build and publishing guide (Arabic): [`docs/DEPLOY_AR.md`](docs/DEPLOY_AR.md)**

## Service setup
See [`SETUP_NEW_SERVICES_AR.md`](SETUP_NEW_SERVICES_AR.md) for Firebase, Supabase, Cloudinary, Zego, Giphy and GitHub Actions secrets. The Firebase files in a fresh archive must be replaced with your own project configuration before running the app.

## Quick start
```bash
cp .env.example .env          # fill with YOUR OWN service keys
flutterfire configure         # generates lib/firebase_options.dart + google-services.json
flutter pub get
flutter run --dart-define-from-file=.env
```

## Release build
```bash
flutter build apk --release --dart-define-from-file=.env          # APK
flutter build appbundle --release --dart-define-from-file=.env    # Play Store AAB
```

## Branding in one place
- App name / contact links / team card: `lib/core/constants/brand_config.dart`
- Colors: `lib/core/design/tokens/colors.dart` and `lib/core/themes/models/app_theme_model.dart`
- Re-brand for another client: `python3 scripts/rebrand.py --new-name "X" --new-pkg x --new-id com.x.app`
