#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build InkKey's compact offline bilingual dictionary.

Inputs (downloaded into Tools/_data, see Tools/fetch_data.sh):
  cedict.txt.gz      CC-CEDICT (https://www.mdbg.net/chinese/dictionary?page=cc-cedict)
  jieba_dict.txt     jieba's word frequency list (MIT)
  google10k.txt      google-10000-english (frequency ordered English words)
  ipa_en_US.txt      open-dict-data/ipa-dict en_US (IPA pronunciation)
  ecdict.csv         skywind3000/ECDICT (English -> Chinese, MIT)

Output:
  Resources/dictionary.tsv

  v2<TAB>cnCount<TAB>enCount
  word<TAB>pinyin<TAB>gloss<TAB>freq          (cnCount lines, 中文)
  word<TAB>ipa<TAB>meaning<TAB>rank           (enCount lines, English)

The line format is deliberately stupid: the keyboard reads it with one linear
pass over the raw bytes and builds the strings directly, so loading 40k+ entries
stays far quicker (and far lighter) than JSONDecoder.  The file is bundled into
both the app and the keyboard extension.

Scale: ~35-50k Chinese words/phrases/idioms (CC-CEDICT readings + jieba
frequency) and 9k English words.  Memory stays around 12-14 MB in the
extension, well under the ~48 MB ceiling.
"""
import csv
import gzip
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "_data")
OUT = os.path.abspath(os.path.join(HERE, "..", "Resources", "dictionary.tsv"))

CJK = re.compile(r"^[\u3400-\u4dbf\u4e00-\u9fff]+$")
CEDICT_LINE = re.compile(r"^(\S+)\s+(\S+)\s+\[([^\]]*)\]\s+/(.*)/\s*$")

# 中文词条入选门槛（jieba 词频）：单字放宽到 60，词组/成语 40。
MIN_FREQ_CHAR = 60
MIN_FREQ_WORD = 40
MAX_GLOSS = 40

DROP_DEF_PREFIXES = (
    "variant of", "old variant", "archaic variant", "Japanese variant",
    "used in", "see ", "surname ", "abbr. for", "erhua variant",
    "also written", "same as", "Taiwan pr.", "CL:",
)


def clean_field(text):
    """One TSV field: no tabs, no newlines, no stray control characters."""
    text = text.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def strip_parentheticals(text):
    """Keeps the words, drops the brackets: '(completed action marker)' ->
    'completed action marker' so the English stays insertable and speakable."""
    text = text.replace("(", " ").replace(")", " ")
    text = text.replace("[", " ").replace("]", " ")
    text = re.sub(r"\s+", " ", text).strip(" ,;/")
    return text


def clean_defs(raw):
    out = []
    for piece in raw.split("/"):
        d = piece.strip()
        if not d:
            continue
        low = d.lower()
        if any(low.startswith(p.lower()) for p in DROP_DEF_PREFIXES):
            continue
        if low.startswith("classifier for"):
            continue
        d = strip_parentheticals(re.sub(r"\s+", " ", d))
        if len(d) > MAX_GLOSS:
            d = d[:MAX_GLOSS - 2].rstrip(" ,;") + "…"
        if d and d.lower() not in [x.lower() for x in out]:
            out.append(d)
        if len(out) == 2:
            break
    return "; ".join(out)


def toneless_pinyin(raw):
    """'Han4 yu3' -> 'han yu' ; 'lu:4' -> 'lv' ; keeps syllable boundaries."""
    syls = []
    for syl in raw.replace("\u00b7", " ").split():
        s = syl.strip().lower()
        if not s:
            continue
        s = re.sub(r"[0-9]", "", s)
        s = s.replace("u:", "v").replace("ü", "v")
        s = re.sub(r"[^a-z]", "", s)
        if s:
            syls.append(s)
    return " ".join(syls)


def load_jieba():
    freq = {}
    path = os.path.join(DATA, "jieba_dict.txt")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 2:
                continue
            w = parts[0]
            try:
                n = int(parts[1])
            except ValueError:
                continue
            if n > freq.get(w, 0):
                freq[w] = n
    return freq


def load_cedict():
    """simplified word -> list of (toneless pinyin, gloss), one per reading."""
    entries = {}
    path = os.path.join(DATA, "cedict.txt.gz")
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            m = CEDICT_LINE.match(line.strip())
            if not m:
                continue
            trad, simp, pinyin, defs = m.groups()
            if not CJK.match(simp) or len(simp) > 4:
                continue
            gloss = clean_defs(defs)
            if not gloss:
                continue
            py = toneless_pinyin(pinyin)
            if not py:
                continue
            bucket = entries.setdefault(simp, [])
            if all(py != p for p, _ in bucket):
                bucket.append((py, gloss))
    return entries


def build_chinese():
    from pypinyin import lazy_pinyin, Style

    freq = load_jieba()
    cedict = load_cedict()
    scored = []
    for word, readings in cedict.items():
        f = freq.get(word, 0)
        if len(word) == 1:
            if f < MIN_FREQ_CHAR:
                continue
        else:
            if f < MIN_FREQ_WORD:
                continue
            if any(ord(ch) > 0x9FFF for ch in word):
                continue
        try:
            py = " ".join(lazy_pinyin(word, style=Style.NORMAL, errors="ignore"))
        except Exception:
            py = ""
        if not py:
            py = readings[0][0]
        # gloss(es) for the reading we actually show, else every reading we have
        matching = [g for p, g in readings if p == py]
        if not matching:
            matching = [g for _, g in readings]
        senses, seen = [], set()
        for blob in matching:
            for part in blob.split("; "):
                key = part.lower()
                if key in seen:
                    continue
                seen.add(key)
                senses.append(part)
                if len(senses) == 2:
                    break
            if len(senses) == 2:
                break
        gloss = clean_field("; ".join(senses))
        py = clean_field(py)
        if not gloss or not py:
            continue
        scored.append((f, word, py, gloss))
    scored.sort(key=lambda x: (-x[0], len(x[1]), x[1]))

    chars = [s for s in scored if len(s[1]) == 1]
    words = [s for s in scored if len(s[1]) >= 2]
    picked = chars + words
    picked.sort(key=lambda x: (-x[0], len(x[1]), x[1]))
    return [[w, py, gloss, str(int(f))] for f, w, py, gloss in picked]


def load_ipa():
    ipa = {}
    path = os.path.join(DATA, "ipa_en_US.txt")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 2:
                continue
            w, p = parts[0].strip().lower(), parts[1].strip()
            if not re.match(r"^[a-z][a-z'’-]*$", w):
                continue
            p = p.split(",")[0].strip().strip("/").strip()
            p = p.replace("/", "")
            if p and w not in ipa:
                ipa[w] = p
    return ipa


def load_ecdict(wanted):
    """English word -> concise Chinese meaning, only for `wanted` (a set)."""
    meanings = {}
    path = os.path.join(DATA, "ecdict.csv")
    csv.field_size_limit(10 * 1024 * 1024)
    with open(path, encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            w = (row.get("word") or "").strip().lower()
            if w not in wanted or w in meanings:
                continue
            tr = (row.get("translation") or "").replace("\\n", "\n").strip()
            if not tr:
                continue
            lines = []
            for x in tr.split("\n"):
                x = re.sub(r"\[[^\]]*\]", " ", x)
                x = re.sub(r"\s+", " ", x).strip(" ,;，；")
                if x and x not in lines:
                    lines.append(x)
            if not lines:
                continue
            # keep up to two senses, each reasonably short
            picked = []
            for x in lines[:3]:
                if len(x) > 34:
                    x = x[:33].rstrip(" ,;，；") + "…"
                picked.append(x)
                if len(picked) == 2:
                    break
            meanings[w] = clean_field("；".join(picked))
    return meanings


def build_english(limit=9000):
    words = []
    seen = set()
    with open(os.path.join(DATA, "google10k.txt"), encoding="utf-8") as fh:
        for line in fh:
            w = line.strip().lower()
            if not w or w in seen:
                continue
            if not re.match(r"^[a-z][a-z'’-]{1,17}$", w):
                continue
            seen.add(w)
            words.append(w)
    wanted = set(words[: limit + 800])
    ipa = load_ipa()
    meanings = load_ecdict(wanted)

    out = []
    for rank, w in enumerate(words):
        if len(out) >= limit:
            break
        m = meanings.get(w)
        if not m:
            continue
        out.append([w, clean_field(ipa.get(w, "")), m, str(10000 - rank)])
    return out


def write_tsv(cn, en):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("v2\t%d\t%d\n" % (len(cn), len(en)))
        for row in cn:
            fh.write("\t".join(row) + "\n")
        for row in en:
            fh.write("\t".join(row) + "\n")
    os.replace(tmp, OUT)


def main():
    if not os.path.isdir(DATA):
        sys.exit("missing Tools/_data — run Tools/fetch_data.sh first")
    cn = build_chinese()
    en = build_english()
    write_tsv(cn, en)
    size = os.path.getsize(OUT)
    chars = sum(1 for r in cn if len(r[0]) == 1)
    print(f"cn={len(cn)} (chars={chars}) en={len(en)} bytes={size} ({size/1024:.0f} KB)")
    print("sample cn:", cn[:2], cn[3000:3002])
    print("sample en:", en[:2], en[500:502])


if __name__ == "__main__":
    main()
