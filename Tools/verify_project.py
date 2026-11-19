#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pre-flight checks for the InkKey project.  Run from the repo root:

    python3 Tools/verify_project.py

Checks the things that bite during 全能签 re-signing and CI builds:
bundle versions, Info.plist keys, entitlements, the keyboard extension
declaration, the dictionary payload and the app icon.
"""

import json
import os
import plistlib
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILS = []
NOTES = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILS.append(message)


def load_plist(rel):
    with open(os.path.join(ROOT, rel), "rb") as fh:
        return plistlib.load(fh)


def main():
    try:
        import yaml
    except ImportError:
        print("PyYAML is required: python3 -m pip install pyyaml")
        return 2

    with open(os.path.join(ROOT, "project.yml"), encoding="utf-8") as fh:
        spec = yaml.safe_load(fh)

    print("project.yml")
    targets = spec.get("targets", {})
    check(set(targets) >= {"InkKey", "InkKeyKeyboard"}, "both targets declared")
    check(targets["InkKey"]["type"] == "application", "InkKey is an application")
    check(targets["InkKeyKeyboard"]["type"] == "app-extension", "InkKeyKeyboard is an app-extension")

    app_settings = targets["InkKey"]["settings"]["base"]
    ext_settings = targets["InkKeyKeyboard"]["settings"]["base"]
    for name, settings in (("InkKey", app_settings), ("InkKeyKeyboard", ext_settings)):
        check(settings.get("MARKETING_VERSION") == "1.0.0", f"{name} MARKETING_VERSION pinned")
        check(settings.get("CURRENT_PROJECT_VERSION") == "1", f"{name} CURRENT_PROJECT_VERSION pinned")
        plist = settings.get("INFOPLIST_FILE", "")
        check(bool(plist) and os.path.isfile(os.path.join(ROOT, plist)), f"{name} INFOPLIST_FILE exists ({plist})")
        ent = settings.get("CODE_SIGN_ENTITLEMENTS", "")
        check(bool(ent) and os.path.isfile(os.path.join(ROOT, ent)), f"{name} entitlements exist ({ent})")
        bundle = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "")
        check(bundle.startswith("com.lin.inkkey"), f"{name} bundle id {bundle}")

    deps = targets["InkKey"].get("dependencies", [])
    check(any(d.get("target") == "InkKeyKeyboard" and d.get("embed") for d in deps),
          "keyboard extension is embedded in the app")

    print("Info.plist")
    app_plist = load_plist(app_settings["INFOPLIST_FILE"])
    ext_plist = load_plist(ext_settings["INFOPLIST_FILE"])
    for label, plist in (("app", app_plist), ("keyboard", ext_plist)):
        check(plist.get("CFBundleShortVersionString") == "$(MARKETING_VERSION)",
              f"{label} short version uses the build setting")
        check(plist.get("CFBundleVersion") == "$(CURRENT_PROJECT_VERSION)",
              f"{label} build number uses the build setting")
    check(app_plist.get("CFBundleIconName") == "AppIcon", "app declares CFBundleIconName")
    check("UILaunchScreen" in app_plist, "app has a launch screen")

    ext = ext_plist.get("NSExtension", {})
    check(ext.get("NSExtensionPointIdentifier") == "com.apple.keyboard-service",
          "keyboard extension point is com.apple.keyboard-service")
    check(str(ext.get("NSExtensionPrincipalClass", "")).endswith("KeyboardViewController"),
          "principal class is KeyboardViewController")
    check(ext.get("NSExtensionAttributes", {}).get("RequestsOpenAccess") is True,
          "RequestsOpenAccess is on (needed for speech + App Group)")

    print("entitlements")
    for rel in (app_settings["CODE_SIGN_ENTITLEMENTS"], ext_settings["CODE_SIGN_ENTITLEMENTS"]):
        ent = load_plist(rel)
        groups = ent.get("com.apple.security.application-groups", [])
        check("group.com.lin.inkkey" in groups, f"{rel} carries group.com.lin.inkkey")

    print("dictionary")
    with open(os.path.join(ROOT, "Resources", "dictionary.json"), encoding="utf-8") as fh:
        data = json.load(fh)
    size = os.path.getsize(os.path.join(ROOT, "Resources", "dictionary.json"))
    check(data.get("v") == 1, "dictionary version 1")
    check(len(data.get("cn", [])) > 10000, f"chinese entries {len(data.get('cn', []))} > 10000")
    check(len(data.get("en", [])) > 8000, f"english entries {len(data.get('en', []))} > 8000")
    check(500_000 <= size <= 2_100_000, f"dictionary size {size/1024/1024:.2f} MB is within 0.5-2 MB")
    bad = [row for row in data["cn"][:500] if len(row) != 4 or not row[0] or not row[2]]
    check(not bad, "chinese rows are [word, pinyin, gloss, freq]")
    bad = [row for row in data["en"][:500] if len(row) != 4 or not row[0] or not row[2]]
    check(not bad, "english rows are [word, ipa, meaning, rank]")

    print("app icon")
    icon_path = os.path.join(ROOT, "InkKey", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    check(os.path.isfile(icon_path), "1024 icon exists")
    if os.path.isfile(icon_path):
        with open(icon_path, "rb") as fh:
            head = fh.read(33)
        width, height = struct.unpack(">II", head[16:24])
        bit_depth, color_type = head[24], head[25]
        check((width, height) == (1024, 1024), f"icon is {width}x{height}")
        check(bit_depth == 8 and color_type == 2, "icon is 8-bit RGB without alpha")

    print("sources")
    swift_files = []
    for base in ("InkKey", "InkKeyKeyboard"):
        for dirpath, _, names in os.walk(os.path.join(ROOT, base)):
            for name in names:
                if name.endswith(".swift"):
                    swift_files.append(os.path.join(dirpath, name))
    check(len(swift_files) >= 12, f"{len(swift_files)} swift files present")
    for rel in ("InkKey/KeyboardViewController.swift",):
        pass
    check(os.path.isfile(os.path.join(ROOT, "InkKeyKeyboard", "KeyboardViewController.swift")),
          "keyboard controller present")
    check(os.path.isfile(os.path.join(ROOT, "InkKeyKeyboard", "KeyboardView.swift")),
          "keyboard view present")

    print()
    if FAILS:
        print(f"{len(FAILS)} check(s) failed")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
