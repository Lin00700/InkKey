//
//  InkDictionary.swift
//  InkKey / InkKeyKeyboard
//
//  Compact offline bilingual T9 dictionary.  Loading is done off the main
//  thread and the entries are kept in flat arrays so the keyboard extension
//  stays comfortably inside its memory ceiling.
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

// MARK: - Store

final class InkDictionaryStore {
    static let shared = InkDictionaryStore()

    private(set) var chinese: [InkEntry] = []
    private(set) var english: [InkEntry] = []
    private(set) var isLoaded = false
    private(set) var loadError: String?

    private var isLoading = false
    private var waiters: [() -> Void] = []

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
            let result: (cn: [InkEntry], en: [InkEntry], error: String?) = autoreleasepool {
                Self.decode()
            }
            DispatchQueue.main.async {
                self.chinese = result.cn
                self.english = result.en
                self.loadError = result.error
                self.isLoaded = result.error == nil
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

    private static func decode() -> ([InkEntry], [InkEntry], String?) {
        guard let url = resourceURLOverride
                ?? Bundle.main.url(forResource: InkShared.dictionaryFileName, withExtension: "json") else {
            return ([], [], "找不到内置词库文件")
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let cn = entries(from: payload.cn, chinese: true)
            let en = entries(from: payload.en, chinese: false)
            return (cn, en, nil)
        } catch {
            return ([], [], "词库解析失败：\(error.localizedDescription)")
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

    // MARK: Querying

    /// Prefix match on the T9 digits, with a second pass on syllable initials
    /// (so "96" also finds 我们 through "w"+"m"). Exact-length matches rank
    /// first, then by corpus frequency.
    func candidates(for buffer: String, mode: InkMode, limit: Int = 24) -> [InkCandidate] {
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
            if lhs.entry.score != rhs.entry.score { return lhs.entry.score > rhs.entry.score }
            return lhs.entry.word < rhs.entry.word
        }

        return hits.prefix(limit).map { hit in
            let entry = hit.entry
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
            } else {
                return InkCandidate(
                    id: "en-\(entry.word)",
                    primary: entry.word,
                    secondary: entry.gloss,
                    phonetic: entry.reading,
                    isChinese: false,
                    speakText: entry.word
                )
            }
        }
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
