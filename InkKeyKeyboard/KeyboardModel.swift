//
//  KeyboardModel.swift
//  InkKeyKeyboard
//
//  State machine for the T9 keyboard: typed digits, candidate list, mode,
//  symbol / number pages and the actions handed back to the host app.
//

import Foundation
import SwiftUI

protocol KeyboardActionHandler: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func insertNewline()
    func advanceToNextInputMode()
}

enum InkCandidatePart {
    case primary
    case secondary
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
    @Published private(set) var buffer: String = ""
    @Published private(set) var candidates: [InkCandidate] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var dictionaryCount: Int = 0
    @Published var toast: String?
    @Published var showsGlobe: Bool = false
    @Published var keyboardHeight: CGFloat = KeyboardMetrics.portraitHeight

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
    /// changed the theme, accent, default mode or the active font.
    func reloadFromSettings() {
        let stored = InkSettings.shared.mode
        if stored != mode {
            mode = stored
            buffer = ""
        }
        loadDictionaryIfNeeded()
        refreshCandidates()
    }

    // MARK: Typing

    func tapDigit(_ digit: String) {
        guard page == .t9 else { return }
        guard buffer.count < 24 else { return }
        buffer.append(digit)
        refreshCandidates()
        InkFeedback.tap()
    }

    func toggleMode() {
        mode = mode.toggled
        buffer = ""
        page = .t9
        InkSettings.shared.mode = mode
        refreshCandidates()
        InkFeedback.soft()
    }

    func backspace() {
        if !buffer.isEmpty {
            buffer.removeLast()
            refreshCandidates()
            InkFeedback.tap()
        } else {
            handler?.deleteBackward()
            InkFeedback.tap()
        }
    }

    func resetBuffer() {
        buffer = ""
        refreshCandidates()
        InkFeedback.soft()
    }

    func space() {
        if let first = candidates.first {
            handler?.insertText(first.primary)
            buffer = ""
            refreshCandidates()
            if mode == .english {
                handler?.insertText(" ")
            }
        } else {
            handler?.insertText(" ")
        }
        InkFeedback.tap()
    }

    func newline() {
        handler?.insertText("\n")
        buffer = ""
        refreshCandidates()
        InkFeedback.tap()
    }

    func insertCandidate(_ candidate: InkCandidate, part: InkCandidatePart) {
        switch (candidate.isChinese, part) {
        case (true, .primary):
            handler?.insertText(candidate.primary)
        case (true, .secondary):
            handler?.insertText(InkCandidate.insertable(candidate.secondary))
        case (false, .primary):
            handler?.insertText(candidate.primary)
        case (false, .secondary):
            handler?.insertText(InkCandidate.insertable(candidate.secondary))
        }
        buffer = ""
        refreshCandidates()
        InkFeedback.tap()
    }

    func insertSymbol(_ symbol: String) {
        handler?.insertText(symbol)
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
        showToast(added ? "已加入生词本 · \(english)" : "生词本里已有 \(english)")
        InkFeedback.soft()
    }

    func showPage(_ target: Page) {
        page = target
        buffer = ""
        refreshCandidates()
        InkFeedback.soft()
    }

    func nextKeyboard() {
        handler?.advanceToNextInputMode()
    }

    // MARK: Helpers

    private func refreshCandidates() {
        guard !buffer.isEmpty else {
            if !candidates.isEmpty { candidates = [] }
            return
        }
        candidates = InkDictionaryStore.shared.candidates(for: buffer, mode: mode)
    }

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
