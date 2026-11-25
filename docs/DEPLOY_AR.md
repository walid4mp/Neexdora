# دليل الإعداد والبناء والنشر — Nexora

> هذا المشروع هو نسخة مُعاد تسميتها من التطبيق الأصلي بنفس طريقة العمل وبهوية بصرية جديدة (ألوان Teal، زوايا أكبر، شعار وأيقونات جديدة).
> **ملاحظة مهمة:** لم تُجرَ عملية بناء (build) داخل بيئة التحضير لأنها لا تحتوي Flutter SDK. كل التعديلات ثابتة (static) وتمت مراجعتها يدوياً، لذا شغّل الخطوات أدناه وأصلح أي تحذير يظهر من `flutter analyze`.

---

## 1) المتطلبات
- Flutter 3.x (Dart ≥ 3.7.2)، Android Studio + JDK 21، Xcode (لـ iOS على macOS فقط)
- حساب **Supabase** (قاعدة بيانات + مصادقة + Realtime + Storage) خاص بصديقك
- مشروع **Firebase** (FCM للإشعارات + Crashlytics)
- حساب **Cloudinary** (رفع الوسائط) ، **ZegoCloud** (المكالمات) ، **Giphy** (GIF) ، ومفاتيح الذكاء الاصطناعي إن استُخدمت في الـ Edge Functions

## 2) الاسم والهوية الحالية
| العنصر | القيمة |
|---|---|
| اسم التطبيق | Nexora |
| Package (Android/iOS) | `com.nexora.app` |
| اسم حزمة Dart | `nexora` |
| Deep link scheme | `nexora://login-callback` |
| Host للروابط | `your-firebase-project-id.web.app` (غيّره لمشروعك) |

**لتغيير الاسم لعميل آخر بأمر واحد:**
```bash
python3 scripts/rebrand.py --new-name "اسمك" --new-pkg yourpkg --new-id com.yourco.yourapp
```
ثم عدّل `lib/core/constants/brand_config.dart` (روابط التواصل، البريد، اسم الفريق؛ اترك أي قيمة فارغة لإخفاء صفها).

## 3) إعداد Supabase (الباك إند)
⚠️ ملف المشروع المرفوع **لا يحتوي** جداول Supabase ولا الـ Edge Functions. يجب نقلها من مشروعك الأصلي:
```bash
supabase login
supabase link --project-ref <OLD_PROJECT_REF>
supabase db dump -f schema.sql                 # الجداول + RLS + الدوال
supabase functions download                    # الـ Edge Functions (إن وجدت)
# ثم على المشروع الجديد:
supabase link --project-ref <NEW_PROJECT_REF>
psql "<NEW_DB_URL>" -f schema.sql
supabase functions deploy
```
الجداول التي يستعملها الكود (أمثلة): `users, messages, groups, group_members, group_message_reads, calls, group_calls, notifications, chat_mutes, comment_mentions, comment_reactions, ai_chat_sessions, ai_chat_messages` + دوال RPC: `cancel_email_change, clear_mfa_recovery_codes, get_my_feedback_quota, join_group_via_invite`. تأكد من إنشاء **Storage buckets** وتفعيل **Realtime** للجداول اللازمة.

في Supabase → Authentication → URL Configuration أضف:
- `nexora://login-callback`
- `https://<firebase-project>.web.app/auth/recovery`

## 4) إعداد Firebase
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id> --platforms=android,ios
```
هذا يولّد `lib/firebase_options.dart` و`android/app/google-services.json` (الموجودان حالياً **قيم placeholder** ولن يعملا قبل ذلك).
فعّل Cloud Messaging، وأنشئ Service Account لإرسال الإشعارات من الـ Edge Function.

## 5) المفاتيح (.env)
```bash
cp .env.example .env     # املأ القيم بمفاتيحك
```
لا ترفع `.env` على GitHub (مُستثنى في `.gitignore`).
**تسجيل الدخول بفيسبوك (اختياري):** ضع App ID و Client Token الحقيقيين في `android/app/src/main/res/values/strings.xml` وفي `AndroidManifest.xml` (القيم الحالية `YOUR_FACEBOOK_*`)، أو أزل الميزة.

## 6) التشغيل
```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs   # إن طلب Hive/الملفات المولّدة
flutter analyze
flutter test
flutter run --dart-define-from-file=.env
```

## 7) التوقيع والبناء للنشر (Android)
```bash
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties   # عدّل كلمات المرور
flutter build appbundle --release --dart-define-from-file=.env   # لـ Google Play (AAB)
flutter build apk --release --split-per-abi --dart-define-from-file=.env  # APK
```
> بدون `key.properties` يُوقَّع البناء بمفتاح debug (للتجربة فقط). احتفظ بملف `.jks` وكلمات المرور في مكان آمن — فقدانها يمنع تحديث التطبيق.

الناتج: `build/app/outputs/bundle/release/app-release.aab` و`build/app/outputs/flutter-apk/`.

## 8) روابط التطبيق (App Links) وصفحة الويب
```bash
keytool -list -v -keystore android/upload-keystore.jks -alias upload   # انسخ SHA-256
```
ضعه في `public/.well-known/assetlinks.json` (بدل `REPLACE_WITH_YOUR_RELEASE_KEY_SHA256`) ثم:
```bash
npm i -g firebase-tools && firebase login
firebase deploy --only hosting
```
لو فعّلت توقيع Play App Signing أضف أيضاً بصمة Play Console.

## 9) النشر على Google Play
1. أنشئ حساب مطوّر ($25 مرة واحدة) ثم Create app.
2. ارفع `app-release.aab`، أكمل: سياسة الخصوصية (الملفات في `assets/docs/`)، Data safety، تصنيف المحتوى.
3. التطبيق يحتوي محتوى مستخدمين → يجب وجود آلية **إبلاغ/حظر** (موجودة) وحذف الحساب.

## 10) CI/CD (GitHub Actions)
Secrets المطلوبة: `GOOGLE_SERVICES_JSON_BASE64`, `FIREBASE_OPTIONS_DART_BASE64`, `DART_DEFINE_ENV_BASE64`, `SUPABASE_FUNCTIONS_URL`, `SUPABASE_ANON_KEY`. التفاصيل في `docs/ci-cd.md`.

## 11) الميزات
دردشة فردية وجماعية • مكالمات صوت/فيديو (فردية وجماعية) • القصص Stories • الريلز Reels • المنشورات والتعليقات والمنشن والتفاعلات • مساعد ذكاء اصطناعي • ملصقات وحزم ملصقات • GIF • مشاركة وإعادة توجيه الرسائل • المصادقة الثنائية 2FA • قفل التطبيق بالبصمة • حظر/كتم • إشعارات FCM • وضع عدم الاتصال (Hive) • عربي/إنجليزي RTL • 12 ثيم.

## 12) ما تم تغييره في هذه النسخة
- **الهوية:** الاسم، `applicationId/bundleId`، حزمة Dart، deep link scheme، أسماء Windows/Linux/macOS/Web.
- **الشكل:** ثيم افتراضي Teal (Aurora) في `colors.dart` و`app_theme_model.dart`، زوايا أكبر (`radii.dart`)، شعار vector جديد (`brand_mark.dart`) بدل SVG الاسم القديم، أيقونات Android/iOS/Web/Windows/macOS وشاشات البداية جديدة، وصور الـ Onboarding معاد تلوينها.
- **إزالة بيانات المالك الأصلي:** مفاتيح Firebase وFacebook وبصمات assetlinks وروابط/بريد/واتساب/صورة صفحة "من نحن" صارت placeholders مُدارة من `brand_config.dart`.
- **إصلاحات:** البناء Release لا ينكسر بغياب `key.properties` (fallback)، إضافة `proguard-rules.pro` المفقود، `.env.example` كامل (Cloudinary/Giphy)، إزالة ملفات `coverage/build/.firebase` من الحزمة.
- **اسم المساعد الذكي** ما زال "Syncra" داخل الكود (ملفات chat_forwarding) — غيّره إن أردت.
- الأصول الفنية (صور الـ Onboarding، الأصوات `incoming_ring.mp3`/`message_tone.mp3`، خطوط) تأكد من حقوق استخدامها قبل النشر التجاري.
