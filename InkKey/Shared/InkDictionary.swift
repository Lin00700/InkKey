//
//  InkDictionary.swift
//  InkKey / InkKeyKeyboard
//
//  Compact offline bilingual dictionary (40k+ Chinese words).  The bundled
//  file is a plain UTF-8 TSV — one line per entry — so loading is a single
//  pass over the raw bytes instead of a JSON decode: quicker to start and far
//  lighter in peak memory, which is what a keyboard extension needs.  The
//  entries are kept in flat arrays so the extension stays comfortably inside
//  its memory ceiling.
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
    /// a…z -> digit, indexed by `ascii - 97`.  A table is several times
    /// quicker than a [Character: Character] lookup, which matters while
    /// 40k entries are loaded and on every keystroke.
    private static let table: [UInt8] = [
        2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6,
        7, 7, 7, 7, 8, 8, 8, 9, 9, 9, 9
    ]

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

    private static func digit(of ascii: UInt8) -> UInt8? {
        if ascii >= 65, ascii <= 90 { return table[Int(ascii - 65)] }   // A-Z
        if ascii >= 97, ascii <= 122 { return table[Int(ascii - 97)] }  // a-z
        return nil
    }

    static func digits<S: StringProtocol>(_ text: S) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            if let d = digit(of: byte) { bytes.append(d + 48) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// "wo men" -> "96" (first letter of every pinyin syllable).
    static func initials(_ pinyin: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pinyin.count)
        var atSyllableStart = true
        for byte in pinyin.utf8 {
            if byte == 32 {
                atSyllableStart = true
                continue
            }
            if atSyllableStart, let d = digit(of: byte) {
                bytes.append(d + 48)
                atSyllableStart = false
            }
        }
        return String(decoding: bytes, as: UTF8.self)
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

    private var wordIndex: [String: [Int32]] = [:]
    private var maxWordDigits = 1
    private var syllableIndex: [String: [InkSyllable]] = [:]
    /// word -> index into `chinese` (an index instead of a second copy of the
    /// gloss keeps 40k entries about 2 MB lighter).
    private var entryIndexByWord: [String: Int] = [:]
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
        var wordIndex: [String: [Int32]] = [:]
        var maxWordDigits = 1
        var syllables: [InkSyllable] = []
        var syllableIndex: [String: [InkSyllable]] = [:]
        var entryIndexByWord: [String: Int] = [:]
        var logTotal: Double = 17.7
    }

    private static func decode() -> Loaded {
        guard let url = resourceURLOverride
                ?? Bundle.main.url(forResource: InkShared.dictionaryFileName, withExtension: "tsv") else {
            return Loaded(cn: [], en: [], error: "找不到内置词库文件", index: DictionaryIndex())
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let parsed = parse(data)
            if let error = parsed.error {
                return Loaded(cn: [], en: [], error: error, index: DictionaryIndex())
            }
            let index = buildIndex(parsed.cn)
            return Loaded(cn: parsed.cn, en: parsed.en, error: nil, index: index)
        } catch {
            return Loaded(cn: [], en: [], error: "词库读取失败：\(error.localizedDescription)", index: DictionaryIndex())
        }
    }

    /// Reads the v2 TSV straight from bytes: header, `cnCount` Chinese lines,
    /// then `enCount` English lines of `word<TAB>reading<TAB>gloss<TAB>score`.
    private static func parse(_ data: Data) -> (cn: [InkEntry], en: [InkEntry], error: String?) {
        var cn: [InkEntry] = []
        var en: [InkEntry] = []
        var failure: String?
        cn.reserveCapacity(42000)
        en.reserveCapacity(9000)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let total = raw.count
            var position = 0
            var lineNumber = 0
            var cnCount = 0
            var enCount = 0
            var parts: [String] = []
            parts.reserveCapacity(4)

            while position < total {
                var end = position
                while end < total && raw[end] != 0x0A { end += 1 }

                if lineNumber == 0 {
                    fields(raw, start: position, end: end, into: &parts)
                    if parts.count >= 3, parts[0] == "v2",
                       let cnValue = Int(parts[1]), let enValue = Int(parts[2]) {
                        cnCount = cnValue
                        enCount = enValue
                    } else {
                        failure = "词库版本不匹配"
                        return
                    }
                } else if end > position {
                    if cn.count < cnCount {
                        if let entry = entry(from: raw, start: position, end: end, chinese: true, parts: &parts) {
                            cn.append(entry)
                        }
                    } else if en.count < enCount {
                        if let entry = entry(from: raw, start: position, end: end, chinese: false, parts: &parts) {
                            en.append(entry)
                        }
                    }
                }
                position = end + 1
                lineNumber += 1
            }
        }
        return (cn, en, failure)
    }

    private static func entry(from raw: UnsafeRawBufferPointer,
                              start: Int,
                              end: Int,
                              chinese: Bool,
                              parts: inout [String]) -> InkEntry? {
        fields(raw, start: start, end: end, into: &parts)
        guard parts.count >= 4 else { return nil }
        let word = parts[0]
        let reading = parts[1]
        let gloss = parts[2]
        guard !word.isEmpty, !gloss.isEmpty else { return nil }
        let score = Int(parts[3]) ?? 0
        let digits = chinese ? T9Mapper.digits(reading) : T9Mapper.digits(word)
        guard !digits.isEmpty else { return nil }
        let initials = chinese ? T9Mapper.initials(reading) : digits
        return InkEntry(
            word: word,
            reading: reading,
            gloss: gloss,
            score: score,
            digits: digits,
            initialDigits: initials,
            isChinese: chinese
        )
    }

    private static func fields(_ raw: UnsafeRawBufferPointer,
                               start: Int,
                               end: Int,
                               into out: inout [String]) {
        out.removeAll(keepingCapacity: true)
        var fieldStart = start
        var index = start
        while index <= end && out.count < 5 {
            if index == end || raw[index] == 0x09 {
                if index > fieldStart {
                    out.append(String(decoding: raw[fieldStart ..< index], as: UTF8.self))
                } else {
                    out.append("")
                }
                fieldStart = index + 1
            }
            index += 1
        }
    }

    /// Everything the keyboard needs for phrase composition, built off-main.
    private static func buildIndex(_ cn: [InkEntry]) -> DictionaryIndex {
        var index = DictionaryIndex()
        var grouped: [String: [Int32]] = [:]
        grouped.reserveCapacity(cn.count / 2)
        var totals: Double = 0
        var syllableWeights: [String: (digits: String, weight: Int)] = [:]

        for (position, entry) in cn.enumerated() {
            totals += Double(max(entry.score, 0)) + 1
            grouped[entry.digits, default: []].append(Int32(position))
            if index.entryIndexByWord[entry.word] == nil {
                index.entryIndexByWord[entry.word] = position
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
        var trimmed: [String: [Int32]] = [:]
        trimmed.reserveCapacity(grouped.count)
        var maxDigits = 1
        for (digits, positions) in grouped {
            if positions.count > 4 {
                let sorted = positions.sorted { cn[Int($0)].score > cn[Int($1)].score }
                trimmed[digits] = Array(sorted.prefix(4))
            } else {
                trimmed[digits] = positions
            }
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
        entryIndexByWord = index.entryIndexByWord
        logTotal = index.logTotal
    }

    // MARK: Handwriting lookups

    /// The dictionary entry behind one Chinese character (pinyin + gloss).
    func entry(forChinese word: String) -> InkEntry? {
        guard isLoaded, let position = entryIndexByWord[word], position < chinese.count else { return nil }
        return chinese[position]
    }

    /// Turns recognised code points into bilingual candidates for the strip.
    func candidates(forCharacters characters: [UInt32], limit: Int = 12) -> [InkCandidate] {
        guard isLoaded else { return [] }
        var out: [InkCandidate] = []
        out.reserveCapacity(min(characters.count, limit))
        var seen = Set<String>()
        for codepoint in characters {
            guard let scalar = UnicodeScalar(codepoint) else { continue }
            var text = ""
            text.unicodeScalars.append(scalar)
            guard seen.insert(text).inserted else { continue }
            if let entry = entry(forChinese: text) {
                out.append(Self.candidate(from: entry))
            } else {
                out.append(InkCandidate(
                    id: "ink-\(text)",
                    primary: text,
                    secondary: "",
                    phonetic: "",
                    isChinese: true,
                    speakText: ""
                ))
            }
            if out.count >= limit { break }
        }
        return out
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
        for entry in english {
            if entry.word.hasPrefix(needle) {
                hits.append(entry)
            } else if entry.word.lowercased().hasPrefix(needle) {
                hits.append(entry)
            }
            if hits.count > 400 { break }
        }
        guard !hits.isEmpty else { return [] }

        hits.sort { lhs, rhs in
            let lhsExact = lhs.word.lowercased() == needle
            let rhsExact = rhs.word.lowercased() == needle
            if lhsExact != rhsExact { return lhsExact }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.word.count != rhs.word.count { return lhs.word.count < rhs.word.count }
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
                    if let positions = wordIndex[key] {
                        for position in positions {
                            let entry = chinese[Int(position)]
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
        for (key, positions) in wordIndex where key.hasPrefix(digits) {
            for position in positions {
                let entry = chinese[Int(position)]
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
                if let position = entryIndexByWord[piece], position < chinese.count {
                    matched = InkCandidate.insertable(chinese[position].gloss)
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
