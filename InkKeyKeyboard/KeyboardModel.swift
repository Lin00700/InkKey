//
//  KeyboardModel.swift
//  InkKeyKeyboard
//
//  State machine for the bilingual keyboard:
//    - Chinese 9-key: T9 digits, locked pinyin syllables, word/phrase
//      candidates and the sentence reference row.
//    - English 26-key: live word buffer, prefix completions, shift state.
//  Also owns the symbol / number pages, the return-key label and the height
//  the keyboard needs for its extra rows.
//

import Foundation
import SwiftUI

protocol KeyboardActionHandler: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func insertNewline()
    func advanceToNextInputMode()
    func hideKeyboard()
    /// Deletes the word before the caret (only when it still matches) and
    /// inserts `text` in its place — used by the English completions.
    func replaceTrailingWord(_ expected: String, with text: String)
}

enum InkCandidatePart {
    case primary
    case secondary
}

enum InkShiftState {
    case off
    case single
    case caps
}

/// The 中文语句 / 英文翻译参考 row.
struct InkSentence {
    let chinese: String
    let english: String
    let isOnline: Bool
    let isPending: Bool
}

final class KeyboardModel: ObservableObject {
    enum Page {
        case t9
        case symbols
        case numbers
    }

    weak var handler: KeyboardActionHandler?

    @Published var mode: InkMode
    @Published private(set) var page: Page = .t9
    /// Chinese: the digits of the syllable in progress.  English: the letters
    /// typed since the last word boundary.
    @Published private(set) var buffer: String = ""
    @Published private(set) var lockedSyllables: [String] = []
    @Published private(set) var syllableOptions: [InkSyllableOption] = []
    @Published private(set) var candidates: [InkCandidate] = []
    @Published private(set) var sentence: InkSentence?
    @Published private(set) var shift: InkShiftState = .off
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var dictionaryCount: Int = 0
    @Published var toast: String?
    @Published var showsGlobe: Bool = false
    @Published var returnKeyLabel: String = "换行"
    @Published var hasFullAccess: Bool = true
    @Published var keyboardHeight: CGFloat = KeyboardMetrics.portraitHeight

    private var baseHeight: CGFloat = KeyboardMetrics.portraitHeight
    private var compositionWords: [String] = []
    private var toastWork: DispatchWorkItem?

    init(mode: InkMode = InkSettings.shared.mode) {
        self.mode = mode
        loadDictionaryIfNeeded()
    }

    // MARK: Dictionary

    func loadDictionaryIfNeeded() {
        if InkDictionaryStore.shared.isLoaded {
            isLoading = false
            dictionaryCount = InkDictionaryStore.shared.totalCount
            refreshCandidates()
            return
        }
        onChangeMain {
            self.isLoading = true
        }
        InkDictionaryStore.shared.load { [weak self] in
            guard let self else { return }
            self.isLoading = false
            self.dictionaryCount = InkDictionaryStore.shared.totalCount
            self.refreshCandidates()
        }
    }

    /// Called when the keyboard becomes visible again — the app may have
    /// changed the theme, accent, default mode, translation settings or font.
    func reloadFromSettings() {
        let stored = InkSettings.shared.mode
        if stored != mode {
            mode = stored
            buffer = ""
            lockedSyllables = []
        }
        loadDictionaryIfNeeded()
        refreshCandidates()
    }

    // MARK: Geometry

    func setBaseHeight(_ value: CGFloat) {
        guard abs(baseHeight - value) > 0.5 else { return }
        baseHeight = value
        recomputeHeight()
    }

    var showsSentenceRow: Bool {
        mode == .chinese && page == .t9 && sentence != nil
    }

    var showsSyllableRow: Bool {
        mode == .chinese && page == .t9 && !syllableOptions.isEmpty
    }

    var topExtraHeight: CGFloat {
        var extra: CGFloat = 0
        if showsSentenceRow { extra += KeyboardMetrics.sentenceRowHeight + KeyboardMetrics.rowSpacing }
        if showsSyllableRow { extra += KeyboardMetrics.syllableRowHeight + KeyboardMetrics.rowSpacing }
        return extra
    }

    private func recomputeHeight() {
        let target = baseHeight + topExtraHeight
        if abs(keyboardHeight - target) > 0.5 {
            keyboardHeight = target
        }
    }

    // MARK: Typing — Chinese 9-key

    func tapDigit(_ digit: String) {
        guard mode == .chinese, page == .t9 else { return }
        guard lockedSyllables.count * 4 + buffer.count < 24 else { return }
        buffer.append(contentsOf: digit)
        refreshCandidates()
        InkFeedback.tap()
    }

    /// Locks a pinyin syllable: "6" + chip ni -> 64 is consumed into 你/呢…
    func selectSyllable(_ option: InkSyllableOption) {
        guard mode == .chinese, page == .t9 else { return }
        var remaining = buffer
        if !option.digits.isEmpty, remaining.hasPrefix(option.digits) {
            remaining.removeFirst(option.digits.count)
        } else {
            remaining += option.suffix
            remaining = ""
        }
        lockedSyllables.append(option.text)
        buffer = remaining
        refreshCandidates()
        InkFeedback.soft()
    }

    func clearSyllableLocks() {
        guard !lockedSyllables.isEmpty else { return }
        lockedSyllables = []
        refreshCandidates()
        InkFeedback.soft()
    }

    // MARK: Typing — English 26-key

    func tapLetter(_ letter: String) {
        guard mode == .english, page == .t9 else { return }
        let text = shift == .off ? letter.lowercased() : letter.uppercased()
        handler?.insertText(text)
        buffer += text
        if shift == .single { shift = .off }
        if buffer.count > 32 { buffer = String(buffer.suffix(32)) }
        refreshCandidates()
        InkFeedback.tap()
    }

    func toggleShift(doubleTap: Bool) {
        if doubleTap {
            shift = shift == .caps ? .off : .caps
        } else {
            shift = shift == .off ? .single : .off
        }
        InkFeedback.soft()
    }

    // MARK: Common keys

    func toggleMode() {
        mode = mode.toggled
        buffer = ""
        lockedSyllables = []
        syllableOptions = []
        shift = .off
        page = .t9
        sentence = nil
        compositionWords = []
        InkSettings.shared.mode = mode
        refreshCandidates()
        InkFeedback.soft()
    }

    func backspace() {
        if !buffer.isEmpty {
            buffer.removeLast()
            refreshCandidates()
            InkFeedback.tap()
            return
        }
        if mode == .chinese, !lockedSyllables.isEmpty {
            lockedSyllables.removeLast()
            refreshCandidates()
            InkFeedback.tap()
            return
        }
        handler?.deleteBackward()
        refreshCandidates()
        InkFeedback.tap()
    }

    func resetBuffer() {
        buffer = ""
        lockedSyllables = []
        shift = .off
        refreshCandidates()
        InkFeedback.soft()
    }

    func space() {
        if mode == .chinese {
            if let first = candidates.first {
                handler?.insertText(first.primary)
                recordPicks(for: first)
            }
            handler?.insertText(" ")
        } else {
            handler?.insertText(" ")
        }
        buffer = ""
        lockedSyllables = []
        shift = .off
        refreshCandidates()
        InkFeedback.tap()
    }

    func newline() {
        handler?.insertNewline()
        buffer = ""
        lockedSyllables = []
        shift = .off
        refreshCandidates()
        InkFeedback.tap()
    }

    func dismissKeyboard() {
        InkSentenceTranslator.shared.cancel()
        handler?.hideKeyboard()
    }

    func insertCandidate(_ candidate: InkCandidate, part: InkCandidatePart) {
        let text: String
        switch (candidate.isChinese, part) {
        case (true, .primary): text = candidate.primary
        case (true, .secondary): text = InkCandidate.insertable(candidate.secondary)
        case (false, .primary): text = candidate.primary
        case (false, .secondary): text = InkCandidate.insertable(candidate.secondary)
        }

        if mode == .english {
            handler?.replaceTrailingWord(buffer, with: text)
        } else {
            handler?.insertText(text)
            recordPicks(for: candidate)
        }
        buffer = ""
        lockedSyllables = []
        shift = .off
        refreshCandidates()
        InkFeedback.tap()
    }

    func insertSymbol(_ symbol: String) {
        handler?.insertText(symbol)
        buffer = ""
        lockedSyllables = []
        shift = .off
        refreshCandidates()
        InkFeedback.tap()
    }

    /// Speaks the English side and files it into the shared 生词本.
    func speak(_ candidate: InkCandidate) {
        let english = candidate.isChinese
            ? InkCandidate.insertable(candidate.secondary)
            : candidate.primary
        let chinese = candidate.isChinese ? candidate.primary : InkCandidate.firstSense(candidate.secondary)
        InkSpeech.shared.speak(english)
        let added = VocabularyStore.shared.add(
            word: english,
            phonetic: candidate.isChinese ? "" : candidate.phonetic,
            meaning: chinese
        )
        recordPicks(for: candidate)
        showToast(added ? "已加入生词本 · \(english)" : "生词本里已有 \(english)")
        InkFeedback.soft()
    }

    // MARK: Sentence row

    func insertSentenceChinese() {
        guard let sentence else { return }
        handler?.insertText(sentence.chinese)
        InkUserFrequency.shared.record(wordsOf(sentence.chinese))
        clearComposition()
        InkFeedback.tap()
    }

    func insertSentenceEnglish() {
        guard let sentence else { return }
        handler?.insertText(sentence.english)
        clearComposition()
        InkFeedback.tap()
    }

    func speakSentence() {
        guard let sentence else { return }
        InkSpeech.shared.speak(sentence.english)
        InkFeedback.soft()
    }

    private func wordsOf(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        if let composition = InkDictionaryStore.shared.composition(forDigits: T9Mapper.digits(text)) {
            return composition.words.map { $0.word }
        }
        return [text]
    }

    private func clearComposition() {
        buffer = ""
        lockedSyllables = []
        sentence = nil
        compositionWords = []
        refreshCandidates()
    }

    // MARK: Pages and keyboards

    func showPage(_ target: Page) {
        page = target
        buffer = ""
        lockedSyllables = []
        syllableOptions = []
        shift = .off
        refreshCandidates()
        InkFeedback.soft()
    }

    func nextKeyboard() {
        handler?.advanceToNextInputMode()
    }

    // MARK: Candidates

    private var canTranslateOnline: Bool {
        hasFullAccess && InkSettings.shared.translateOnline
    }

    private func refreshCandidates() {
        guard page == .t9 else {
            if !candidates.isEmpty { candidates = [] }
            updateSyllableOptions()
            updateSentence(nil)
            recomputeHeight()
            return
        }

        switch mode {
        case .chinese:
            refreshChinese()
        case .english:
            refreshEnglish()
        }
        recomputeHeight()
    }

    private func refreshChinese() {
        updateSyllableOptions()
        let digits = T9Mapper.digits(lockedSyllables.joined(separator: " ")) + buffer
        guard !digits.isEmpty else {
            if !candidates.isEmpty { candidates = [] }
            compositionWords = []
            updateSentence(nil)
            return
        }

        let boost: (String) -> Double = { InkUserFrequency.shared.boost(for: $0) }
        var list = InkDictionaryStore.shared.candidates(
            for: digits,
            mode: .chinese,
            limit: 22,
            boost: boost
        )

        let composition = InkDictionaryStore.shared.composition(forDigits: digits, boost: boost)
        compositionWords = composition?.words.map { $0.word } ?? []
        if let composition, composition.isMultiWord, composition.text.count >= 3 {
            let phrase = InkCandidate(
                id: "phrase-\(composition.text)",
                primary: composition.text,
                secondary: composition.gloss,
                phonetic: composition.pinyin,
                isChinese: true,
                speakText: composition.gloss,
                isPhrase: true
            )
            list.removeAll { $0.primary == composition.text }
            list.insert(phrase, at: 0)
        }
        candidates = Array(list.prefix(24))
        updateSentence(composition)
    }

    private func refreshEnglish() {
        if buffer.isEmpty {
            if !candidates.isEmpty { candidates = [] }
            return
        }
        candidates = InkDictionaryStore.shared.englishCompletions(prefix: buffer, limit: 22)
    }

    private func updateSyllableOptions() {
        guard mode == .chinese, page == .t9, !buffer.isEmpty else {
            if !syllableOptions.isEmpty { syllableOptions = [] }
            return
        }
        syllableOptions = InkDictionaryStore.shared.syllableOptions(for: buffer)
    }

    private func updateSentence(_ composition: InkComposition?) {
        guard mode == .chinese,
              page == .t9,
              let composition,
              composition.isMultiWord,
              composition.text.count >= 3 else {
            if sentence != nil {
                sentence = nil
                recomputeHeight()
            }
            return
        }

        let chinese = composition.text
        if sentence?.chinese == chinese { return }

        let offline = composition.gloss.isEmpty
            ? InkDictionaryStore.shared.offlineGloss(forChinese: chinese)
            : composition.gloss
        let online = canTranslateOnline
        sentence = InkSentence(
            chinese: chinese,
            english: offline,
            isOnline: false,
            isPending: online
        )
        recomputeHeight()
        guard online else { return }

        InkSentenceTranslator.shared.request(chinese) { [weak self] result in
            guard let self, let current = self.sentence, current.chinese == chinese else { return }
            guard result.isOnline, !result.english.isEmpty else { return }
            self.sentence = InkSentence(
                chinese: chinese,
                english: result.english,
                isOnline: true,
                isPending: false
            )
        }
    }

    private func recordPicks(for candidate: InkCandidate) {
        if candidate.isPhrase {
            InkUserFrequency.shared.record(compositionWords.isEmpty ? [candidate.primary] : compositionWords)
        } else if candidate.isChinese {
            InkUserFrequency.shared.record(candidate.primary)
        }
    }

    // MARK: Toast

    private func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimationIfPossible { self.toast = text }
        let work = DispatchWorkItem { [weak self] in
            self?.withAnimationIfPossible { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func withAnimationIfPossible(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            withAnimation(.easeInOut(duration: 0.15), body)
        } else {
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.15), body) }
        }
    }

    private func onChangeMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }
}
