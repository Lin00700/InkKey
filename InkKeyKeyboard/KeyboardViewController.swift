//
//  KeyboardViewController.swift
//  InkKeyKeyboard
//
//  Hosts the SwiftUI keyboard, owns the text proxy and keeps the shared
//  settings / fonts / dictionary fresh every time the keyboard appears.
//

import Combine
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, KeyboardActionHandler {

    private let model = KeyboardModel()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        // Register the user's imported fonts before the first draw.
        InkFontCenter.shared.registerAllCustomFonts()

        model.handler = self
        model.showsGlobe = needsInputModeSwitchKey
        model.hasFullAccess = hasFullAccess

        let root = KeyboardRootView(model: model)
        let host = UIHostingController(rootView: root)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController = host

        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.portraitHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        // The keyboard grows when the sentence row / syllable strip appears.
        model.$keyboardHeight
            .removeDuplicates()
            .sink { [weak self] height in
                DispatchQueue.main.async { self?.applyKeyboardHeight(height) }
            }
            .store(in: &cancellables)

        model.loadDictionaryIfNeeded()
        syncReturnKey()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        InkSettings.shared.reload()
        InkFontCenter.shared.reloadFromDefaults()
        model.showsGlobe = needsInputModeSwitchKey
        model.hasFullAccess = hasFullAccess
        model.reloadFromSettings()
        syncReturnKey()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
    }

    private func updateKeyboardHeight() {
        guard view.bounds.width > 1 else { return }
        // The keyboard view itself is wider than it is tall in portrait, so the
        // orientation has to come from the screen.
        let screen = view.window?.windowScene?.screen.bounds ?? UIScreen.main.bounds
        let isLandscape = screen.width > screen.height
        let target = isLandscape ? KeyboardMetrics.landscapeHeight : KeyboardMetrics.portraitHeight
        model.setBaseHeight(target)
        applyKeyboardHeight(model.keyboardHeight)
    }

    private func applyKeyboardHeight(_ height: CGFloat) {
        if abs((heightConstraint?.constant ?? 0) - height) > 0.5 {
            heightConstraint?.constant = height
        }
        if abs(preferredContentSize.height - height) > 0.5 {
            preferredContentSize = CGSize(width: 0, height: height)
        }
    }

    private func syncReturnKey() {
        let label: String
        switch textDocumentProxy.returnKeyType ?? .default {
        case .search: label = "搜索"
        case .send: label = "发送"
        case .go: label = "前往"
        case .done: label = "完成"
        case .next: label = "下一项"
        case .join: label = "加入"
        case .route: label = "路线"
        case .emergencyCall: label = "紧急"
        case .continue: label = "继续"
        default: label = "换行"
        }
        if model.returnKeyLabel != label {
            model.returnKeyLabel = label
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Nothing to mirror: the composing buffer belongs to this keyboard only.
        syncReturnKey()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        syncReturnKey()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        syncReturnKey()
    }

    // MARK: - KeyboardActionHandler

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func insertNewline() {
        textDocumentProxy.insertText("\n")
    }

    override func advanceToNextInputMode() {
        super.advanceToNextInputMode()
    }

    /// Closes the keyboard — the ⌄ key in the candidate bar.
    func hideKeyboard() {
        dismissKeyboard()
    }

    /// Swaps the partial English word for a completion.
    func replaceTrailingWord(_ expected: String, with text: String) {
        let proxy = textDocumentProxy
        var count = 0
        if let context = proxy.documentContextBeforeInput {
            if !expected.isEmpty, context.hasSuffix(expected) {
                count = expected.count
            } else {
                for character in context.reversed() {
                    if character.isLetter {
                        count += 1
                    } else {
                        break
                    }
                }
            }
        } else {
            // No Full Access: the composing buffer is all we know about.
            count = expected.count
        }
        count = min(max(count, 0), 48)
        for _ in 0 ..< count {
            proxy.deleteBackward()
        }
        proxy.insertText(text)
    }

    // MARK: - Clipboard

    /// 粘贴: whatever is on the pasteboard, straight into the document.
    func pasteFromClipboard() -> Int {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return 0 }
        let clipped = String(text.prefix(20000))
        textDocumentProxy.insertText(clipped)
        return clipped.count
    }

    /// 复制: the selection when there is one, otherwise the line before the
    /// caret, so the key is still useful on a plain text field.
    func copySelectionToClipboard() -> Int {
        let proxy = textDocumentProxy
        var value: String?
        if let selected = proxy.selectedText, !selected.isEmpty {
            value = selected
        } else if let context = proxy.documentContextBeforeInput, !context.isEmpty {
            let line = context.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? context
            let picked = line.isEmpty ? context : line
            value = String(picked.suffix(400))
        }
        guard let text = value, !text.isEmpty else { return 0 }
        UIPasteboard.general.string = text
        return text.count
    }

    /// 剪切: only acts on a selection — deleting text the user did not point at
    /// would be far too easy to do by accident.
    func cutSelectionToClipboard() -> Int {
        let proxy = textDocumentProxy
        guard let selected = proxy.selectedText, !selected.isEmpty else { return 0 }
        UIPasteboard.general.string = selected
        let count = min(selected.count, 4000)
        for _ in 0 ..< count {
            proxy.deleteBackward()
        }
        return count
    }
}
