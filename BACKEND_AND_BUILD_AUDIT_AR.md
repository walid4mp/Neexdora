# Nexora — تقرير الفحص والتعديلات

## ملخص الأرشيف
- الأرشيف الأصلي سليم ويمكن فتحه.
- يحتوي المشروع على 1,442 ملفًا بعد فك الضغط، منها 1,165 ملف Dart و23 ملف اختبار Dart.
- تم فحص 8 ملفات YAML/YML؛ جميعها قابلة للتحليل نحويًا.
- تم التحقق من وجود مجلدات الأصول المعلنة في `pubspec.yaml`.
- لا يوجد في هذه النسخة مجلد `supabase/` أو `backend/` أو `functions/`.

## التعديلات المضافة في هذه النسخة
1. إضافة `tool/validate_pub_config.py` للتحقق من إنشاء `.dart_tool/package_config.json` وحل حزمة `flutter_lints`.
2. إضافة خطوة تحقق بعد `flutter pub get` في CI وRelease؛ إذا لم تُحل الحزمة فسيظهر خطأ واضح قبل التنسيق والتحليل.
3. إضافة workflow يدوي `.github/workflows/format.yml` لتنسيق ملفات Dart باستخدام Flutter 3.44.3 نفسه المثبت في CI، ثم إنشاء commit عادي ودفعه إلى الفرع المحدد. لا يستخدم force push.
4. تحديث هذا التقرير ليطابق محتويات الأرشيف الذي تم فحصه.

## سبب تحذير flutter_lints
- `pubspec.yaml` يحتوي بالفعل على `flutter_lints: ^5.0.0` ضمن `dev_dependencies`.
- `pubspec.lock` يحتوي الحزمة `flutter_lints` بالإصدار `5.0.0`.
- `analysis_options.yaml` يستخدم المسار الصحيح `package:flutter_lints/flutter.yaml`.
- التحذير يعني أن محلل Dart لم يجد الحزمة في package configuration المحلية، غالبًا لأن `flutter pub get` لم يعمل أو لم ينجح. تشغيل `dart format` وحده لا ينزّل الحزم ولا ينشئ `.dart_tool/package_config.json`.
- لا تحذف `include` ولا تعطل lint rules لإخفاء التحذير.

## إعدادات تحتاج حسابات المالك
- `lib/firebase_options.dart` و`android/app/google-services.json` يحتويان قيم Firebase تجريبية/placeholder، وليسا إعداد Firebase صالحًا للتشغيل الفعلي.
- `.env.example` قالب فقط ويحتوي قيمًا إرشادية، وليس مفاتيح خدمات حقيقية.
- ملف `supabase-keep-alive.yml` يحتاج GitHub secrets صحيحة، كما أن وظيفة `keep-alive` نفسها غير موجودة في الأرشيف الحالي.
- لا يوجد `supabase/` أو `backend/`، لذلك لم يمكن تدقيق migrations أو Edge Functions أو مخطط قاعدة البيانات.

## حدود التحقق
- لم يتوفر Flutter SDK أو Dart SDK في بيئة الفحص، لذلك لم يتم تشغيل `flutter pub get` أو `dart format` أو `flutter analyze` أو `flutter test` أو بناء APK/AAB.
- فحوص YAML وJSON وسلامة ZIP وفحص وجود المسارات وفحص أنماط الأسرار النصية هي فحوص ساكنة فقط؛ لا تثبت أن التطبيق يبني أو أن الخدمات تعمل.
- يجب تشغيل GitHub Actions بعد رفع هذه النسخة، ثم استكمال Firebase وDart-define وAndroid signing secrets قبل إصدار Release موقّع.

## ملفات وهوية لا تغيّر دون موافقة
- `applicationId`: `com.nexora.app`
- اسم التطبيق: Nexora
- لا تستبدل upload keystore القديم أو تغيّر قاعدة بيانات فعلية دون نسخة احتياطية.
