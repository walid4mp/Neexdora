# CI/CD — Nexora

The workflows use Flutter 3.44.3, JDK 21, and the Android Gradle configuration in this repository.

## Workflows
- `ci.yml`: format, analyze, tests, and an optional debug APK build when Firebase config is supplied.
- `release.yml`: manually builds AAB, APK, or both. It requires production dart-defines, real Firebase configuration, and an Android upload keystore.

See [`../SETUP_NEW_SERVICES_AR.md`](../SETUP_NEW_SERVICES_AR.md) for the Arabic setup guide and exact GitHub secret names.

## Signing safety
Release builds intentionally fail when `android/key.properties` is absent. Do not replace an existing Play App Signing upload key. Keep the keystore and passwords outside the repository.

## Backend
The uploaded source archive does not contain the `supabase/` directory, migrations, or Edge Functions. CI cannot validate or deploy backend resources until the actual backend source is added.
