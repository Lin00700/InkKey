#!/bin/sh
# Fetch the upstream data used by build_dictionary.py into Tools/_data.
set -e
cd "$(dirname "$0")"
mkdir -p _data
cd _data
[ -f cedict.txt.gz ]   || curl -sSL -o cedict.txt.gz "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
[ -f jieba_dict.txt ]  || curl -sSL -o jieba_dict.txt "https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt"
[ -f google10k.txt ]   || curl -sSL -o google10k.txt "https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-usa.txt"
[ -f ipa_en_US.txt ]   || curl -sSL -o ipa_en_US.txt "https://raw.githubusercontent.com/open-dict-data/ipa-dict/master/data/en_US.txt"
[ -f ecdict.csv ]      || curl -sSL -o ecdict.csv "https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv"
echo "data ready in $(pwd)"
