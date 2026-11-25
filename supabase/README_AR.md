# باك إند Nexora (Supabase) — دليل التطبيق

الملفات في `supabase/migrations/` مبنية من قراءة كود التطبيق (الجداول والأعمدة وأسماء الدوال وأشكال النتائج). نفّذها **بالترتيب**:

| الملف | المحتوى |
|---|---|
| `001_schema.sql` | الجداول والفهارس والـ triggers (إنشاء بروفايل عند التسجيل، عدّادات اللايك/التعليق/الملصقات) |
| `002_rls_realtime.sql` | دوال الصلاحيات، سياسات RLS لكل الجداول، تفعيل Realtime |
| `003_rpc_core.sql` | الحساب، 2FA، حالة النظام، الإبلاغ، الدردشة، الذكاء الاصطناعي، المجموعات، التفاعلات، الملصقات |
| `004_rpc_feeds_lists.sql` | قائمة المحادثات، ترتيب الصفحة الرئيسية، منشورات البروفايل/المجموعة، البحث، قائمة المجموعات |
| `005_rpc_people_groups.sql` | الاكتشاف، البحث عن أشخاص، الأصدقاء، نظرة الملف الشخصي، أعضاء المجموعة |
| `006_rpc_stories_reels_groups.sql` | مشاهدو القصص، الريلز، ملف المجموعة وطلبات الانضمام، المجموعات المشتركة |
| `007_admin_moderation.sql` | أدوار الإدارة، الحظر/الإيقاف/التحذير، سجل التدقيق، مراجعة البلاغات، منع المحظورين من الكتابة، حالة الإيقاف الحقيقية |
| `008_storage.sql` | Storage buckets (أنواع وأحجام مسموحة) + سياسات الوصول |
| `009_cron_jobs.sql` | pg_cron: حذف القصص المنتهية، إغلاق المكالمات العالقة، تنظيف، مزامنة الريلز، + إشعارات طلبات الانضمام |

## التنفيذ
**الطريقة 1 — لوحة Supabase:** SQL Editor ← الصق كل ملف ونفّذه بالترتيب (001 → 009).
**الطريقة 2 — CLI:**
```bash
supabase link --project-ref <YOUR_REF>
supabase db push        # ينفّذ المجلد supabase/migrations
```

## بعد التنفيذ (إعدادات من اللوحة)
1. **Authentication → Providers:** فعّل Email وGoogle وFacebook حسب الحاجة، وفعّل **MFA (TOTP)** إن أردت المصادقة الثنائية.
2. **Authentication → URL Configuration:** أضف `nexora://login-callback` وصفحة الاستعادة على الـ hosting.
3. **Database → Replication:** تأكد أن الجداول ظاهرة في publication `supabase_realtime` (الملف 002 يضيفها).
4. ضع `SUPABASE_URL` و`SUPABASE_ANON_KEY` في `.env` للتطبيق.
5. لتفعيل وضع الصيانة/تحديث إجباري: عدّل الصف الوحيد في `app_system_control`:
```sql
update app_system_control set min_supported_version = '1.0.0', recommended_version = '1.0.0' where id = 1;
```

## اختبار سريع (SQL Editor)
```sql
select count(*) from information_schema.tables where table_schema = 'public';       -- ~55 جدول
select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and prosecdef order by 1;                                  -- الدوال
```
ثم سجّل حسابين من التطبيق وجرّب: إضافة صديق، دردشة، منشور، قصة، مجموعة.

## Edge Functions (مضافة)
| الدالة | الوظيفة |
|---|---|
| `send-notification` | إشعارات FCM v1 (رسائل، مكالمات، مجموعات، إعجابات، تعليقات، منشن، صداقات، متابعة…) — data-only وبأولوية عالية فتصل والتطبيق مغلق |
| `generate-livekit-token` | توكن المكالمات (LiveKit) بعد التحقق أن المستخدم طرف في المكالمة/عضو في المجموعة |
| `ai-gateway` | الذكاء الاصطناعي (Gemini + احتياطي Groq) مع حصص يومية وحد للدقيقة وتسجيل الاستهلاك |
| `delete-media-asset` | حذف وسائط Cloudinary + الصف (للمالك/المشرف فقط) + تفريغ طابور الحذف |
| `link-preview` | معاينة الروابط (محمي من SSRF) |
| `sync-reels` | مزامنة Shorts من قنوات يوتيوب |
| `admin-action` | حظر/إيقاف/تحذير/رفع الحظر/معالجة البلاغات (الصلاحية تُفرض داخل Postgres) |

### النشر
```bash
supabase link --project-ref <REF>
supabase db push                                  # 001..009
cp supabase/.env.example supabase/.env            # املأ الأسرار
supabase secrets set --env-file supabase/.env
supabase functions deploy send-notification generate-livekit-token ai-gateway delete-media-asset link-preview sync-reels admin-action
```
(`config.toml` يضبط `verify_jwt` لكل دالة.)

### pg_cron وإشعارات قاعدة البيانات
1. فعّل الامتدادين **pg_cron** و**pg_net** (Dashboard ← Database ← Extensions).
2. خزّن في Vault (SQL Editor):
```sql
select vault.create_secret('https://<REF>.supabase.co', 'project_url');
select vault.create_secret('<نفس قيمة CRON_SECRET>', 'cron_secret');
```
3. أعد تشغيل `009_cron_jobs.sql` ثم تحقق: `select jobname, schedule, active from cron.job where jobname like 'nexora-%';` (يجب ظهور 5 مهام) و`select * from cron.job_run_details order by start_time desc limit 10;`.

### أول مدير (Owner)
```sql
insert into public.app_admins (user_id, role) select id, 'owner' from public.users where email = 'YOUR_EMAIL';
```
بعدها: `admin-action` بالـ JWT الخاص بك (`ban/suspend/warn/unban/resolve_report/set_role`).

## الاختبارات
`supabase/tests/001_smoke_and_rls.sql` (16 فحصاً: التسجيل، الصداقة، المنشورات والعدّادات، الرسائل، القصص، المجموعات، الحظر، RLS بحسابات مختلفة، حذف القصص المنتهية). شغّله على قاعدة **اختبارية** بعد الهجرات:
```bash
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/001_smoke_and_rls.sql
```
يعمل داخل transaction ويُلغى بالكامل (rollback).

## ما لا يغطيه هذا الباك إند
- ميزات الإدارة الأخرى خارج الحظر والبلاغات (لوحة أدمن بصرية) غير مبنية.
- Supabase Storage مُجهَّز لكن التطبيق يرفع إلى **Cloudinary** حالياً.
- مزامنة الريلز تحتاج `YOUTUBE_API_KEY` وصفوفاً في `reel_channels`.

## ⚠️ حالة التحقق (صريحة)
لم يُنفَّذ أي SQL على Postgres حقيقي ولم تُشغَّل أي Edge Function (لا Deno/Postgres/شبكة في بيئة التحضير). التحقق الذي تم: فحص صياغة TypeScript بـ Node، وتوازن الأقواس في SQL، وقراءة عقود التطبيق. **شغّل ملف الاختبار أعلاه وأرسل لي أي خطأ.**
