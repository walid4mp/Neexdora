#!/usr/bin/env python3
"""Validate that pub get generated a package config containing flutter_lints."""
from __future__ import annotations

import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pubspec = root / "pubspec.yaml"
lockfile = root / "pubspec.lock"
config = root / ".dart_tool" / "package_config.json"

if not pubspec.is_file() or not lockfile.is_file():
    sys.exit("Missing pubspec.yaml or pubspec.lock; run this from the project root.")
if not config.is_file():
    sys.exit(
        "Missing .dart_tool/package_config.json. Run `flutter pub get` first; "
        "Dart formatting alone does not download or resolve packages."
    )

try:
    data = json.loads(config.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    sys.exit(f"Cannot read .dart_tool/package_config.json: {exc}")

packages = data.get("packages", [])
flutter_lints = next(
    (item for item in packages if item.get("name") == "flutter_lints"), None
)
if flutter_lints is None:
    sys.exit(
        "`flutter_lints` is not in the resolved package config. "
        "Check dev_dependencies in pubspec.yaml, then run `flutter pub get`."
    )

print("Pub package configuration is valid; flutter_lints is resolved.")
