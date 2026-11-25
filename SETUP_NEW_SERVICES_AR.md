# Nexora — إعداد الخدمات وGitHub Actions (العربية)

## مهم قبل التشغيل
هذا المستودع يحتوي تطبيق Flutter، لكنه لا يحتوي مجلد `supabase/` أو ملفات migrations/Edge Functions في الأرشيف الذي تم فحصه. كما أن ملفات Firebase الموجودة داخل الأرشيف كانت قيمًا تجريبية (`your-firebase-project-id` وحقول أرقام صفرية)، وليست إعداد مشروع Firebase فعلي. لذلك لا يمكن اعتبار تسجيل الدخول أو الإشعارات أو قاعدة البيانات جاهزة بمجرد نجاح بناء APK.

لا ترفع مفاتيح Service Role أو مفاتيح خاصة أو كلمات مرور إلى Git أو داخل تطبيق Flutter.

## 1. إعداد Flutter محليًا
1. ثبّت Flutter **3.44.3** وJDK **21**.
2. انسخ `.env.example` إلى `.env` واملأ القيم من حساباتك.
3. أنشئ إعداد Firebase الحقيقي باستخدام FlutterFire CLI:
   - `dart pub global activate flutterfire_cli`
   - `flutterfire configure`
   - اختر Android package `com.nexora.app`، وأضف iOS إذا كنت ستبنيه.
4. تأكد من استبدال ملف `android/app/google-services.json` التجريبي وملف `lib/firebase_options.dart` التجريبي بملفات مشروعك الحقيقية.
5. نفّذ:
   - `flutter pub get`
   - `flutter analyze`
   - `flutter test`
   - `flutter build apk --debug --dart-define-from-file=.env`

## 2. القيم المطلوبة في `.env`
الملف JSON، ويجب أن تكون أسماء الحقول مطابقة تمامًا:
- `SUPABASE_URL`: رابط مشروع Supabase.
- `SUPABASE_ANON_KEY`: مفتاح publishable/anon فقط. لا تستخدم `service_role`.
- `CLOUDINARY_CLOUD_NAME` و`CLOUDINARY_UPLOAD_PRESET`: إعدادات Cloudinary. استخدم unsigned preset محدود الصلاحيات، ولا تضع API secret في التطبيق.
- `ZEGO_APP_ID`: رقم تطبيق Zego.
- `FCM_PROJECT_ID`: معرف مشروع Firebase.
- `GIPHY_API_KEY`: مفتاح Giphy.

ملاحظة: مفاتيح `dart-define` المضمنة في تطبيق الهاتف يمكن استخراجها من التطبيق؛ لا تستخدمها كأسرار خادم. يجب أن تتم العمليات الحساسة في Backend/Edge Functions.

## 3. GitHub Actions Secrets
من GitHub: Repository → Settings → Secrets and variables → Actions → New repository secret.

أضف هذه الأسماء:
| Secret | المحتوى |
|---|---|
| `GOOGLE_SERVICES_JSON_BASE64` | ملف `android/app/google-services.json` الحقيقي بعد Base64 |
| `FIREBASE_OPTIONS_DART_BASE64` | ملف `lib/firebase_options.dart` الحقيقي بعد Base64 |
| `DART_DEFINE_ENV_BASE64` | ملف `.env` المحلي بصيغة JSON بعد Base64 (لـ CI debug) |
| `DART_DEFINE_ENV_PROD_BASE64` | ملف إعداد إنتاج منفصل بصيغة JSON بعد Base64 |
| `ANDROID_KEYSTORE_BASE64` | ملف keystore الخاص بالتوقيع بعد Base64 |
| `ANDROID_STORE_PASSWORD` | كلمة مرور keystore |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح |
| `ANDROID_KEY_ALIAS` | alias المفتاح |

على Termux/Linux، اطبع قيمة Base64 ثم انسخها إلى GitHub Secrets:
```bash
base64 -w 0 android/app/google-services.json
base64 -w 0 lib/firebase_options.dart
base64 -w 0 .env
base64 -w 0 .env.production
base64 -w 0 android/app/upload-keystore.jks
```
لا ترسل هذه القيم في المحادثات ولا تضعها في ملفات عامة. إذا لم يكن لديك keystore قديم لتطبيق منشور، أنشئ واحدًا واحتفظ بنسخة آمنة خارج GitHub. لا تستبدل keystore لتطبيق منشور لأن ذلك قد يمنع تحديثه.

## 4. نتائج GitHub Actions
- `CI`: يعمل تنسيق Dart والتحليل والاختبارات دون مفاتيح.
- بناء APK Debug في CI يصبح متاحًا عند إعداد أسرار Firebase و`DART_DEFINE_ENV_BASE64`؛ عند غياب إعداد Firebase سيظهر إشعار واضح ويستمر فحص الكود والاختبارات فقط.
- `Release`: يتطلب كل أسرار Firebase وبيئة الإنتاج وkeystore. يفشل برسالة واضحة إذا كان أي سر ناقصًا، ولا يوقّع إصدار Release بمفتاح Debug.
- `release.yml` ينتج AAB أو APK أو كليهما حسب الاختيار اليدوي في Actions → Release → Run workflow.

## 5. Supabase / Backend
الأرشيف الحالي لا يتضمن مجلد `supabase/` ولا migrations ولا Edge Functions. لا تنفّذ SQL عشوائيًا على مشروعك الحالي. أضف مجلد Supabase الصحيح من نسخة الباك إند الأصلية، ثم راجع migrations وRLS وStorage policies قبل تطبيقها على قاعدة بيانات حقيقية.
