#!/usr/bin/env python3
"""Добавляет в CineBoard/Resources/Localizable.xcstrings ключи, найденные компилятором.

Сначала соберите проект (xcodebuild build), затем:
    python3 scripts/sync_strings.py [путь/к/DerivedData]

Существующие переводы не трогаются; ключи, которых больше нет в коде, помечаются как stale.
"""
import glob
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
catalog_path = os.path.join(root, "CineBoard", "Resources", "Localizable.xcstrings")
derived = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Developer/Xcode/DerivedData")

keys = set()
for path in glob.glob(os.path.join(derived, "**", "CineBoard.build", "**", "*.stringsdata"), recursive=True):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for entry in data.get("tables", {}).get("Localizable", []):
        keys.add(entry["key"])

with open(catalog_path, encoding="utf-8") as f:
    catalog = json.load(f)
strings = catalog["strings"]

added = [k for k in sorted(keys) if k not in strings]
for k in added:
    strings[k] = {}
stale = 0
for k, v in strings.items():
    if k not in keys:
        v["extractionState"] = "stale"
        stale += 1
    elif v.get("extractionState") == "stale":
        del v["extractionState"]

catalog["strings"] = dict(sorted(strings.items()))
with open(catalog_path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
    f.write("\n")
print(f"keys in code: {len(keys)}, added: {len(added)}, stale: {stale}")
