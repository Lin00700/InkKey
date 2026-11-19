//
//  InkDictionary.swift
//  InkKey / InkKeyKeyboard
//
//  Compact offline bilingual dictionary.  Loading is done off the main thread
//  and the entries are kept in flat arrays so the keyboard extension stays
//  comfortably inside its memory ceiling.
//
//  Besides plain T9 prefix matching it also provides
//    - pinyin syllable options for the syllable strip on the 9-key layout,
//    - a Viterbi (shortest-path) segmentation that assembles multi-word
//      Chinese phrases and sentences from a digit string,
//    - prefix completions for the 26-key English layout.
//

import Foundation

// MARK: - T9 mapping

enum T9Mapper {
    static let letterToDigit: [Character: Character] = [
        "a": "2", "b": "2", "c": "2",
        "d": "3", "e": "3", "f": "3",
        "g": "4", "h": "4", "i": "4",
        "j": "5", "k": "5", "l": "5",
        "m": "6", "n": "6", "o": "6",
        "p": "7", "q": "7", "r": "7", "s": "7",
        "t": "8", "u": "8", "v": "8",
        "w": "9", "x": "9", "y": "9", "z": "9"
    ]

    static func digits<S: StringProtocol>(_ text: S) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text.lowercased() {
            if let d = letterToDigit[ch] {
                out.append(d)
            }
        }
        return out
    }

    /// "wo men" -> "96" (first letter of every pinyin syllable).
    static func initials(_ pinyin: String) -> String {
        var out = ""
        for syllable in pinyin.split(separator: " ") {
            if let first = syllable.first, let d = letterToDigit[first] {
                out.append(d)
            }
        }
        return out
    }
}

// MARK: - Entries

struct InkEntry {
    let word: String
    let reading: String      // pinyin (Chinese) or IPA (English)
    let gloss: String        // English gloss (Chinese) or Chinese meaning (English)
    let score: Int
    let digits: String
    let initialDigits: String
    let isChinese: Bool
}

struct InkCandidate: Identifiable, Equatable {
    let id: String
    let primary: String
    let secondary: String
    let phonetic: String
    let isChinese: Bool
    let speakText: String
    /// A whole composed phrase/sentence rather than one dictionary word.
    var isPhrase: Bool = false

    /// First sense only — this is what gets inserted when the user taps the
    /// translation row, so it has to read like a word, not a paragraph.
    static func firstSense(_ gloss: String) -> String {
        let parts = gloss
            .replacingOccurrences(of: "；", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.first ?? gloss
    }

    /// What actually lands in the text field when the translation is tapped:
    /// one sense, without dictionary part-of-speech prefixes such as "n. ".
    static func insertable(_ gloss: String) -> String {
        var text = firstSense(gloss)
        let pattern = "^[A-Za-z]{1,4}\\. "
        while let range = text.range(of: pattern, options: [.regularExpression]) {
            text.removeSubrange(range)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Syllables and compositions

struct InkSyllable {
    let text: String
    let digits: String
    let weight: Int
}

/// One chip on the pinyin syllable strip.
struct InkSyllableOption: Identifiable, Equatable {
    let text: String
    let digits: String
    /// Digits to append when the typed digits are a prefix of this syllable.
    let suffix: String
    /// The typed digits already spell the whole syllable.
    let isExact: Bool
    var id: String { text }
}

/// A candidate assembled from several dictionary words (智能词组 / 整句).
struct InkComposition {
    let words: [InkEntry]
    let text: String
    let pinyin: String
    let gloss: String
    let isPartial: Bool
    let score: Double

    var isMultiWord: Bool { words.count >= 2 }
}

// MARK: - Store

final class InkDictionaryStore {
    static let shared = InkDictionaryStore()

    private(set) var chinese: [InkEntry] = []
    private(set) var english: [InkEntry] = []
    private(set) var isLoaded = false
    private(set) var loadError: String?
    private(set) var syllableList: [InkSyllable] = []

    private var isLoading = false
    private var waiters: [() -> Void] = []

    private var wordIndex: [String: [InkEntry]] = [:]
    private var maxWordDigits = 1
    private var syllableIndex: [String: [InkSyllable]] = [:]
    private var glossByWord: [String: String] = [:]
    private var logTotal: Double = 17.7

    private init() {}

    var totalCount: Int { chinese.count + english.count }

    /// Loads the bundled dictionary once, off the main thread.
    func load(completion: (() -> Void)? = nil) {
        if isLoaded {
            completion?()
            return
        }
        if let completion {
            waiters.append(completion)
        }
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result: Loaded = autoreleasepool { Self.decode() }
            DispatchQueue.main.async {
                self.chinese = result.cn
                self.english = result.en
                self.loadError = result.error
                self.isLoaded = result.error == nil
                self.apply(result.index)
                self.isLoading = false
                let pending = self.waiters
                self.waiters.removeAll()
                pending.forEach { $0() }
            }
        }
    }

    /// Lets the offline dictionary checker in Tools/DictionaryCheck run the very
    /// same decoding + matching code on a desktop toolchain.
    static var resourceURLOverride: URL?

    private struct Loaded {
        let cn: [InkEntry]
        let en: [InkEntry]
        let error: String?
        let index: DictionaryIndex
    }

    private struct DictionaryIndex {
        var wordIndex: [String: [InkEntry]] = [:]
        var maxWordDigits = 1
        var syllables: [InkSyllable] = []
        var syllableIndex: [String: [InkSyllable]] = [:]
        var glossByWord: [String: String] = [:]
        var logTotal: Double = 17.7
    }

    private static func decode() -> Loaded {
        guard let url = resourceURLOverride
                ?? Bundle.main.url(forResource: InkShared.dictionaryFileName, withExtension: "json") else {
            return Loaded(cn: [], en: [], error: "找不到内置词库文件", index: DictionaryIndex())
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let cn = entries(from: payload.cn, chinese: true)
            let en = entries(from: payload.en, chinese: false)
            let index = buildIndex(cn)
            return Loaded(cn: cn, en: en, error: nil, index: index)
        } catch {
            return Loaded(cn: [], en: [], error: "词库解析失败：\(error.localizedDescription)", index: DictionaryIndex())
        }
    }

    private struct Payload: Decodable {
        let v: Int
        let cn: [[String]]
        let en: [[String]]
    }

    private static func entries(from rows: [[String]], chinese: Bool) -> [InkEntry] {
        var out: [InkEntry] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            guard row.count >= 4 else { continue }
            let word = row[0]
            let reading = row[1]
            let gloss = row[2]
            let score = Int(row[3]) ?? 0
            guard !word.isEmpty, !gloss.isEmpty else { continue }
            let digits = chinese ? T9Mapper.digits(reading) : T9Mapper.digits(word)
            guard !digits.isEmpty else { continue }
            let initials = chinese ? T9Mapper.initials(reading) : digits
            out.append(InkEntry(
                word: word,
                reading: reading,
                gloss: gloss,
                score: score,
                digits: digits,
                initialDigits: initials,
                isChinese: chinese
            ))
        }
        return out
    }

    /// Everything the keyboard needs for phrase composition, built off-main.
    private static func buildIndex(_ cn: [InkEntry]) -> DictionaryIndex {
        var index = DictionaryIndex()
        var grouped: [String: [InkEntry]] = [:]
        grouped.reserveCapacity(cn.count)
        var totals: Double = 0
        var syllableWeights: [String: (digits: String, weight: Int)] = [:]

        for entry in cn {
            totals += Double(max(entry.score, 0)) + 1
            grouped[entry.digits, default: []].append(entry)
            if index.glossByWord[entry.word] == nil {
                index.glossByWord[entry.word] = entry.gloss
            }
            for syllable in entry.reading.split(separator: " ") {
                let text = String(syllable)
                let digits = T9Mapper.digits(text)
                guard !digits.isEmpty else { continue }
                if let existing = syllableWeights[text] {
                    syllableWeights[text] = (existing.digits, existing.weight + entry.score)
                } else {
                    syllableWeights[text] = (digits, entry.score)
                }
            }
        }

        // Keep only the strongest few words per digit string for the DP.
        var trimmed: [String: [InkEntry]] = [:]
        trimmed.reserveCapacity(grouped.count)
        var maxDigits = 1
        for (digits, entries) in grouped {
            let sorted = entries.sorted { $0.score > $1.score }
            trimmed[digits] = Array(sorted.prefix(4))
            maxDigits = max(maxDigits, digits.count)
        }
        index.wordIndex = trimmed
        index.maxWordDigits = maxDigits
        index.logTotal = log(max(totals, 2))

        let syllables = syllableWeights
            .map { InkSyllable(text: $0.key, digits: $0.value.digits, weight: $0.value.weight) }
            .sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.text < rhs.text
            }
        index.syllables = syllables

        var byDigits: [String: [InkSyllable]] = [:]
        for syllable in syllables {
            byDigits[syllable.digits, default: []].append(syllable)
        }
        index.syllableIndex = byDigits
        return index
    }

    private func apply(_ index: DictionaryIndex) {
        wordIndex = index.wordIndex
        maxWordDigits = index.maxWordDigits
        syllableList = index.syllables
        syllableIndex = index.syllableIndex
        glossByWord = index.glossByWord
        logTotal = index.logTotal
    }

    // MARK: Querying — plain candidates

    /// Prefix match on the T9 digits, with a second pass on syllable initials
    /// (so "96" also finds 我们 through "w"+"m").  Exact-length matches rank
    /// first, then by corpus frequency plus the user's own picks.
    func candidates(for buffer: String,
                    mode: InkMode,
                    limit: Int = 24,
                    boost: ((String) -> Double)? = nil) -> [InkCandidate] {
        guard isLoaded, !buffer.isEmpty else { return [] }
        let pool = mode == .chinese ? chinese : english
        var hits: [(penalty: Int, entry: InkEntry)] = []
        hits.reserveCapacity(64)

        for entry in pool {
            if entry.digits.hasPrefix(buffer) {
                hits.append((entry.digits.count - buffer.count, entry))
            } else if entry.initialDigits.hasPrefix(buffer) {
                hits.append((entry.digits.count - buffer.count + 4, entry))
            }
        }
        guard !hits.isEmpty else { return [] }

        hits.sort { lhs, rhs in
            if lhs.penalty != rhs.penalty { return lhs.penalty < rhs.penalty }
            let lhsScore = Double(lhs.entry.score) + (boost?(lhs.entry.word) ?? 0) * 900
            let rhsScore = Double(rhs.entry.score) + (boost?(rhs.entry.word) ?? 0) * 900
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.entry.word < rhs.entry.word
        }

        return hits.prefix(limit).map { hit in
            Self.candidate(from: hit.entry)
        }
    }

    static func candidate(from entry: InkEntry) -> InkCandidate {
        if entry.isChinese {
            let english = InkCandidate.firstSense(entry.gloss)
            return InkCandidate(
                id: "cn-\(entry.word)",
                primary: entry.word,
                secondary: english,
                phonetic: entry.reading,
                isChinese: true,
                speakText: english
            )
        }
        return InkCandidate(
            id: "en-\(entry.word)",
            primary: entry.word,
            secondary: entry.gloss,
            phonetic: entry.reading,
            isChinese: false,
            speakText: entry.word
        )
    }

    // MARK: Querying — English prefix completions (26-key layout)

    func englishCompletions(prefix: String, limit: Int = 20) -> [InkCandidate] {
        guard isLoaded, !prefix.isEmpty else { return [] }
        let needle = prefix.lowercased()
        var hits: [InkEntry] = []
        for entry in english where entry.word.lowercased().hasPrefix(needle) {
            hits.append(entry)
            if hits.count > 400 { break }
        }
        guard !hits.isEmpty else { return [] }

        hits.sort { lhs, rhs in
            let lhsExact = lhs.word.lowercased() == needle
            let rhsExact = rhs.word.lowercased() == needle
            if lhsExact != rhsExact { return lhsExact }
            if lhs.word.count != rhs.word.count { return lhs.word.count < rhs.word.count }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.word < rhs.word
        }
        return hits.prefix(limit).map { Self.candidate(from: $0) }
    }

    // MARK: Querying — pinyin syllables

    /// Chips for the syllable strip: syllables whose digits match the digits
    /// typed so far, either completing them ("64" -> ni, mi, min…) or already
    /// contained in them ("642" -> ni + leftover "2").
    func syllableOptions(for digits: String, limit: Int = 12) -> [InkSyllableOption] {
        guard isLoaded, !digits.isEmpty else { return [] }
        var out: [InkSyllableOption] = []
        var seen = Set<String>()

        var exact: [InkSyllableOption] = []
        var completing: [InkSyllableOption] = []
        var contained: [InkSyllableOption] = []

        for syllable in syllableList {
            if syllable.digits == digits {
                if seen.insert(syllable.text).inserted {
                    exact.append(InkSyllableOption(text: syllable.text,
                                                   digits: syllable.digits,
                                                   suffix: "",
                                                   isExact: true))
                }
            } else if syllable.digits.hasPrefix(digits) {
                if seen.insert(syllable.text).inserted {
                    let suffix = String(syllable.digits.dropFirst(digits.count))
                    completing.append(InkSyllableOption(text: syllable.text,
                                                       digits: syllable.digits,
                                                       suffix: suffix,
                                                       isExact: false))
                }
            } else if digits.hasPrefix(syllable.digits), syllable.digits.count >= 2 {
                if seen.insert(syllable.text).inserted {
                    contained.append(InkSyllableOption(text: syllable.text,
                                                       digits: syllable.digits,
                                                       suffix: "",
                                                       isExact: false))
                }
            }
            if exact.count + completing.count + contained.count > 80 { break }
        }

        out = exact + completing + contained
        return Array(out.prefix(limit))
    }

    // MARK: Querying — phrase / sentence composition

    /// Viterbi segmentation of a digit string into dictionary words.  The
    /// highest-scoring cover becomes one candidate, e.g. "96636" -> 我们 or
    /// "5468426" -> 今天.  A trailing partial syllable is completed with the
    /// best matching word so the row fills in while typing.
    func composition(forDigits digits: String,
                     boost: ((String) -> Double)? = nil) -> InkComposition? {
        guard isLoaded, !digits.isEmpty, !wordIndex.isEmpty else { return nil }
        let chars = Array(digits)
        let n = chars.count
        let unreachable = -Double.greatestFiniteMagnitude

        var best = [Double](repeating: unreachable, count: n + 1)
        var prev = [Int](repeating: -1, count: n + 1)
        var chosen = [InkEntry?](repeating: nil, count: n + 1)
        best[0] = 0

        var i = 0
        while i < n {
            if best[i] > unreachable {
                let maxLength = min(maxWordDigits, n - i)
                var length = 1
                while length <= maxLength {
                    let key = String(chars[i ..< (i + length)])
                    if let entries = wordIndex[key] {
                        for entry in entries {
                            let score = best[i] + segmentScore(entry, boost: boost)
                            if score > best[i + length] {
                                best[i + length] = score
                                prev[i + length] = i
                                chosen[i + length] = entry
                            }
                        }
                    }
                    length += 1
                }
            }
            i += 1
        }

        var end = n
        var partial: InkEntry?
        if best[n] == unreachable {
            // No full cover yet: take the longest reachable prefix and let the
            // rest be completed by the strongest word that starts with it.
            var j = n - 1
            while j > 0 && best[j] == unreachable { j -= 1 }
            guard j > 0, best[j] != unreachable else { return nil }
            let remainder = String(chars[j...])
            partial = completionEntry(forDigits: remainder, boost: boost)
            guard partial != nil else { return nil }
            end = j
        }

        var words: [InkEntry] = []
        var cursor = end
        while cursor > 0 {
            let previous = prev[cursor]
            guard previous >= 0, let entry = chosen[cursor] else { return nil }
            words.append(entry)
            cursor = previous
        }
        words.reverse()
        if let partial {
            words.append(partial)
        }
        guard !words.isEmpty else { return nil }

        let text = words.map { $0.word }.joined()
        let pinyin = words.map { $0.reading }.joined(separator: " ")
        let gloss = words.map { InkCandidate.insertable($0.gloss) }.joined(separator: " ")
        let score = best[end] + (partial.map { segmentScore($0, boost: boost) - 1.2 } ?? 0)
        return InkComposition(
            words: words,
            text: text,
            pinyin: pinyin,
            gloss: gloss,
            isPartial: partial != nil,
            score: score
        )
    }

    private func completionEntry(forDigits digits: String, boost: ((String) -> Double)?) -> InkEntry? {
        guard !digits.isEmpty else { return nil }
        var bestEntry: InkEntry?
        var bestScore = -Double.greatestFiniteMagnitude
        for (key, entries) in wordIndex where key.hasPrefix(digits) {
            for entry in entries {
                let score = Double(entry.score) + (boost?(entry.word) ?? 0) * 900
                if score > bestScore {
                    bestScore = score
                    bestEntry = entry
                }
            }
        }
        return bestEntry
    }

    /// Unigram language-model score: log P(word) + a length bonus so 我们
    /// beats 我 + 哦 + 鄂 + 哦.
    private func segmentScore(_ entry: InkEntry, boost: ((String) -> Double)?) -> Double {
        let frequency = Double(max(entry.score, 1))
        var score = log(frequency) - logTotal
        score += Double(entry.word.count - 1) * 1.2
        if entry.word.count == 1 { score -= 0.8 }
        score += boost?(entry.word) ?? 0
        return score
    }

    /// Offline English chain used when no translation endpoint is reachable.
    func offlineGloss(forChinese text: String) -> String {
        guard !text.isEmpty else { return "" }
        var pieces: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            var matched: String?
            var length = min(4, text.distance(from: index, to: text.endIndex))
            while length >= 1 {
                let end = text.index(index, offsetBy: length)
                let piece = String(text[index ..< end])
                if let gloss = glossByWord[piece] {
                    matched = InkCandidate.insertable(gloss)
                    pieces.append(matched ?? "")
                    index = end
                    break
                }
                length -= 1
            }
            if matched == nil {
                index = text.index(after: index)
            }
        }
        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Random entries for the vocabulary review warm-up (kept tiny on purpose).
    func sampleEntries(mode: InkMode, count: Int) -> [InkCandidate] {
        guard isLoaded else { return [] }
        let pool = mode == .chinese ? chinese : english
        guard !pool.isEmpty else { return [] }
        var picked: [InkEntry] = []
        var attempts = 0
        while picked.count < count && attempts < count * 8 {
            attempts += 1
            let index = Int.random(in: 0 ..< min(pool.count, 4000))
            picked.append(pool[index])
        }
        return picked.map { entry in
            InkCandidate(
                id: "sample-\(entry.word)",
                primary: entry.word,
                secondary: entry.isChinese ? InkCandidate.firstSense(entry.gloss) : entry.gloss,
                phonetic: entry.reading,
                isChinese: entry.isChinese,
                speakText: entry.isChinese ? InkCandidate.firstSense(entry.gloss) : entry.word
            )
        }
    }
}
