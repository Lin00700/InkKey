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
    dict_path = os.path.join(ROOT, "Resources", "dictionary.tsv")
    check(os.path.isfile(dict_path), "Resources/dictionary.tsv exists")
    with open(dict_path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        rows = fh.readlines()
    check(header and header[0] == "v2", "dictionary header is v2")
    cn_count = int(header[1]) if len(header) > 1 else 0
    en_count = int(header[2]) if len(header) > 2 else 0
    size = os.path.getsize(dict_path)
    check(cn_count >= 35000, f"chinese entries {cn_count} >= 35000")
    check(en_count >= 8000, f"english entries {en_count} >= 8000")
    check(len(rows) == cn_count + en_count, f"{len(rows)} data lines match the header")
    check(2_000_000 <= size <= 4_500_000, f"dictionary size {size/1024/1024:.2f} MB is within 2-4.5 MB")
    bad = [row for row in rows[:500] if len(row.rstrip("\n").split("\t")) != 4]
    check(not bad, "rows are word<TAB>reading<TAB>gloss<TAB>score")
    chars = sum(1 for row in rows[:cn_count] if len(row.split("\t", 1)[0]) == 1)
    check(chars >= 4000, f"{chars} single characters in the Chinese set")

    print("handwriting")
    hw_path = os.path.join(ROOT, "Resources", "handwriting.bin")
    check(os.path.isfile(hw_path), "Resources/handwriting.bin exists")
    if os.path.isfile(hw_path):
        with open(hw_path, "rb") as fh:
            blob = fh.read()
        check(blob[:4] == b"IKHX", "handwriting magic is IKHX")
        version, pps, _ = struct.unpack_from("<HBB", blob, 4)
        (hw_count,) = struct.unpack_from("<I", blob, 8)
        check(version == 1, "handwriting layout version 1")
        check(6 <= pps <= 12, f"{pps} points per stroke")
        check(hw_count >= 6500, f"{hw_count} characters in the handwriting set")
        expected = 12 + hw_count * 16
        total_points = 0
        for index in range(hw_count):
            strokes = blob[12 + index * 16 + 4]
            offset = struct.unpack_from("<I", blob, 12 + index * 16 + 8)[0]
            total_points = max(total_points, offset + strokes * pps)
        check(expected + total_points * 2 == len(blob),
              f"point block matches {hw_count} records ({len(blob)} bytes)")

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

    print("keyboard features")

    def read(rel):
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            return fh.read()

    shared = "InkKey/Shared"
    for rel in ("InkKeyKeyboard/EnglishKeyboard.swift",
                "InkKeyKeyboard/ExtraRows.swift",
                f"{shared}/InkSentenceTranslator.swift",
                f"{shared}/InkUserFrequency.swift"):
        check(os.path.isfile(os.path.join(ROOT, rel)), f"{rel} exists")

    strip = read("InkKeyKeyboard/CandidateStrip.swift")
    check("keyboard.chevron.compact.down" in strip, "dismiss key lives in the always-visible candidate bar")
    check("dismissKeyboard()" in strip, "dismiss key calls into the model")

    controller = read("InkKeyKeyboard/KeyboardViewController.swift")
    check("func hideKeyboard()" in controller, "controller implements hideKeyboard")
    check("dismissKeyboard()" in controller, "controller really closes the keyboard")
    check("returnKeyType" in controller, "return key label follows the host")
    check("replaceTrailingWord" in controller, "english completions replace the partial word")
    check("hasFullAccess" in controller, "full access is passed to the model")

    english = read("InkKeyKeyboard/EnglishKeyboard.swift")
    check("qwerty" in english.lower(), "26-key QWERTY rows present")
    check("ShiftKey" in english, "shift key present")
    check("InkRepeatKey" in english, "backspace with hold-to-repeat in the 26-key layout")

    model_swift = read("InkKeyKeyboard/KeyboardModel.swift")
    check("tapLetter" in model_swift, "model takes direct letter input")
    check("selectSyllable" in model_swift, "model locks pinyin syllables")
    check("updateSentence" in model_swift, "model owns the sentence reference row")
    check("keyboardHeight" in model_swift, "model reports the height its extra rows need")
    check("toggleHandwriting" in model_swift, "model owns the 手写 mode")
    check("recognizeInk" in model_swift, "model runs handwriting recognition")
    for name in ("func paste()", "func copy()", "func cut()", "func clearInput()"):
        check(name in model_swift, f"editing action {name} present")

    view = read("InkKeyKeyboard/KeyboardView.swift")
    check("SentenceReferenceRow" in view, "sentence row wired into the root view")
    check("InlineSyllableStrip" in view, "pinyin chips wired into the root view")
    check("model.returnKeyLabel" in view, "return key label reaches the keys")
    check("EditActionStrip" in view, "editing toolbar wired into the root view")
    for label in ("粘贴", "复制", "剪切", "清空", "换行"):
        check(label in view, f"toolbar offers {label}")
    check("model.handwriting" in view, "keys area switches to the ink pad")

    pad = read("InkKeyKeyboard/HandwritingPadView.swift")
    for label in ("撤一笔", "重写", "空格", "换行"):
        check(label in pad, f"ink pad offers {label}")
    check("DragGesture" in pad, "ink pad collects touches")
    check("model.recognizeInk" in pad, "ink pad reports strokes to the model")

    recognizer = read(f"{shared}/HandwritingRecognizer.swift")
    check("IKHX" in recognizer or "magic" in recognizer, "recogniser validates the template file")
    check("func recognize(strokes" in recognizer, "recogniser exposes recognize(strokes:)")
    check("resample" in recognizer, "strokes are resampled before matching")

    dictionary_swift = read(f"{shared}/InkDictionary.swift")
    check("func composition(forDigits" in dictionary_swift, "phrase/sentence Viterbi composition present")
    check("func syllableOptions" in dictionary_swift, "pinyin syllable options present")
    check("func englishCompletions" in dictionary_swift, "english prefix completions present")
    check("boost" in dictionary_swift, "user frequency can boost ranking")

    shared_swift = read(f"{shared}/InkShared.swift")
    for key in ("translateOnline", "translateEndpoint", "translateModel", "translateKey"):
        check(key in shared_swift, f"translation setting {key} is shared through the App Group")

    translator = read(f"{shared}/InkSentenceTranslator.swift")
    check("translate.googleapis.com" in translator, "built-in zero-key translation endpoint")
    check("chat/completions" in translator, "custom OpenAI-compatible endpoint supported")
    check("debounce" in translator, "debounced lookups")

    print("sources")
    swift_files = []
    for base in ("InkKey", "InkKeyKeyboard"):
        for dirpath, _, names in os.walk(os.path.join(ROOT, base)):
            for name in names:
                if name.endswith(".swift"):
                    swift_files.append(os.path.join(dirpath, name))
    check(len(swift_files) >= 15, f"{len(swift_files)} swift files present")
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
