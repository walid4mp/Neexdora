#!/usr/bin/env python3
"""Re-brand this project again (new client / new name) in one command.

Usage (from project root):
  python3 scripts/rebrand.py --new-name "Zenly" --new-pkg zenly --new-id com.zenly.app

Defaults assume the current brand (Nexora / nexora / com.nexora.app).
Also edit lib/core/constants/brand_config.dart, replace icons (see docs/DEPLOY_AR.md),
and re-run `flutterfire configure`.
"""
import argparse, os, shutil
ap = argparse.ArgumentParser()
ap.add_argument('--old-name', default='Nexora'); ap.add_argument('--new-name', required=True)
ap.add_argument('--old-pkg', default='nexora');  ap.add_argument('--new-pkg', required=True)
ap.add_argument('--old-id', default='com.nexora.app'); ap.add_argument('--new-id', required=True)
a = ap.parse_args()
EXT = {'.dart','.yaml','.yml','.kts','.xml','.json','.md','.html','.plist','.pbxproj','.xcconfig','.cc','.txt','.rc','.cpp','.kt','.arb','.gradle','.properties','.cmake','.xcscheme','.entitlements','.swift'}
SKIP = {'coverage','build','.dart_tool','.git','node_modules'}
n = 0
for d, dirs, files in os.walk('.'):
    dirs[:] = [x for x in dirs if x not in SKIP]
    for f in files:
        if f in ('pubspec.lock', 'rebrand.py') or os.path.splitext(f)[1] not in EXT: continue
        p = os.path.join(d, f)
        try: s = open(p, encoding='utf-8').read()
        except Exception: continue
        o = s
        s = s.replace(a.old_id, a.new_id).replace(f'package:{a.old_pkg}/', f'package:{a.new_pkg}/')
        s = s.replace(a.old_pkg, a.new_pkg).replace(a.old_name, a.new_name)
        if s != o: open(p, 'w', encoding='utf-8').write(s); n += 1
old = 'android/app/src/main/kotlin/' + a.old_id.replace('.', '/')
new = 'android/app/src/main/kotlin/' + a.new_id.replace('.', '/')
if os.path.isdir(old) and old != new:
    os.makedirs(new, exist_ok=True)
    for f in os.listdir(old): shutil.move(os.path.join(old, f), new)
    try: os.removedirs(old)   # removes only EMPTY old parent dirs
    except OSError: pass
print(f'Updated {n} files. Now: flutter clean && flutter pub get')
