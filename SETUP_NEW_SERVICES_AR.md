# إعداد الخدمات الجديدة لـ Nexora (Firebase · Supabase · Cloudinary · Giphy · LiveKit · Keystore)

> تم تنظيف المستودع من كل المفاتيح والإعدادات القديمة. **لا شيء يعمل قبل أن تضيف مفاتيحك وتختبرها** — وأي بناء ينقصه سر سيفشل برسالة تذكر أسماء الأسرار الناقصة (ولا يتخطى بناء الـ APK بصمت).
> ⚠️ الـ `google-services.json` الموجود في المستودع **قيم Placeholder** والـ CI يرفضه عمداً.
> **ملاحظة:** المكالمات في هذا الكود تعمل عبر **LiveKit** وليس Zego (لا يوجد استدعاء Zego فعلي في التطبيق).

## 1) GitHub Secrets (Settings ← Secrets and variables ← Actions ← New repository secret)
| Secret | مطلوب لـ | من أين |
|---|---|---|
| `SUPABASE_URL` | كل البناءات | Supabase ← Project Settings ← API ← Project URL |
| `SUPABASE_ANON_KEY` | كل البناءات | نفس الصفحة ← `anon` / Publishable key (المفتاح العام فقط) |
| `CLOUDINARY_CLOUD_NAME` | كل البناءات | Cloudinary Dashboard |
| `CLOUDINARY_UPLOAD_PRESET` | كل البناءات | Settings ← Upload ← Upload presets ← أنشئ preset من نوع **Unsigned** |
| `GIPHY_API_KEY` | اختياري (تحذير فقط) | developers.giphy.com ← Create an App (SDK/API) |
| `GOOGLE_SERVICES_JSON_BASE64` | كل البناءات | Firebase ← Project settings ← Android app ← `google-services.json` ثم Base64 |
| `ANDROID_KEYSTORE_BASE64` | Release/AAB | ملف `.jks` بصيغة Base64 |
| `ANDROID_STORE_PASSWORD` | Release/AAB | كلمة مرور الـ keystore |
| `ANDROID_KEY_PASSWORD` | Release/AAB | كلمة مرور المفتاح |
| `ANDROID_KEY_ALIAS` | Release/AAB | اسم المفتاح (مثلاً `upload`) |

`lib/firebase_options.dart` يُولَّد تلقائياً من `google-services.json` أثناء البناء (`scripts/make_firebase_options.py`)، فلا حاجة لـ FlutterFire CLI ولا لسر ثانٍ.

## 2) Firebase
1. console.firebase.google.com ← أنشئ مشروعاً ← Add app ← **Android**.
2. اسم الحزمة بالضبط: **`com.nexora.app`** (أي اسم آخر سيرفضه الـ CI).
3. نزّل `google-services.json` ← حوّله Base64 (القسم 5) ← ضعه في `GOOGLE_SERVICES_JSON_BASE64`.
4. فعّل **Cloud Messaging**. لإرسال الإشعارات من Edge Function: Project settings ← Service accounts ← **Generate new private key** ← ضع محتوى JSON كاملاً في Supabase Secret باسم `FIREBASE_SERVICE_ACCOUNT` (انظر `supabase/README_AR.md`). **لا تضعه في Flutter ولا في GitHub.**

## 3) Supabase
أنشئ مشروعاً، ثم نفّذ `supabase/migrations/001…009` بالترتيب، وانشر الدوال، وضع أسرار الدوال (`supabase/README_AR.md`). مفتاح `service_role` **لا يوضع أبداً** في التطبيق أو في GitHub Secrets الخاصة بالبناء.

## 4) Cloudinary وLiveKit
- Cloudinary: التطبيق يرفع بـ **unsigned preset** (آمن). `CLOUDINARY_API_KEY/SECRET` تذهب فقط إلى Supabase Secrets (حذف الملفات من الخادم).
- LiveKit (المكالمات): cloud.livekit.io ← مشروع جديد ← خذ `URL` و`API Key` و`API Secret` ← Supabase Secrets: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.

## 5) التحويل إلى Base64 من Termux
```bash
pkg install coreutils openjdk-17 git
base64 -w0 google-services.json > gs.b64      # انسخ محتوى gs.b64 إلى السر
base64 -w0 upload-keystore.jks  > ks.b64
cat gs.b64   # (للنسخ فقط — لا تشاركه في أي مكان)
```

## 6) إنشاء Keystore جديد
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
احفظ الملف وكلمتَي المرور في مكان آمن (فقدانها = عدم القدرة على تحديث التطبيق على Google Play). **لا تحذف أي keystore قديم قبل التأكد أنك لا تحتاجه لتطبيق منشور.** لا ترفع `.jks` إلى GitHub (مستثنى في `.gitignore`).

## 7) تشغيل البناء
- **Debug APK:** يعمل تلقائياً مع كل push على `main` (Actions ← CI ← artifact `nexora-debug-apk`).
- **Release APK/AAB:** Actions ← **Release (APK / AAB)** ← Run workflow ← اختر `apk` / `aab` / `both`.

## 8) اختبار كل خدمة (بعد إضافة المفاتيح)
| الخدمة | الاختبار |
|---|---|
| Supabase | شغّل workflow **Supabase keep-alive** يدوياً ← يجب HTTP 200؛ ثم سجّل حساباً من التطبيق |
| Firebase/FCM | سجّل دخولاً بجهازين وأرسل رسالة وأنت مغلق التطبيق في الجهاز الثاني |
| Cloudinary | انشر صورة؛ إن فشل الرفع تأكد أن الـ preset **Unsigned** |
| Giphy | افتح تعليقاً ← GIF |
| LiveKit | اتصال صوتي بين حسابين |
| AI | افتح المساعد وأرسل رسالة (يحتاج `GEMINI_API_KEY`) |
| Keystore | شغّل Release؛ الخطوة تتحقق من فتح الـ keystore قبل البناء |
