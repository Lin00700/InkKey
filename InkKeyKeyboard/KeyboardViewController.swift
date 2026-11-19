//
//  KeyboardViewController.swift
//  InkKeyKeyboard
//
//  Hosts the SwiftUI keyboard, owns the text proxy and keeps the shared
//  settings / fonts / dictionary fresh every time the keyboard appears.
//

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, KeyboardActionHandler {

    private let model = KeyboardModel()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        // Register the user's imported fonts before the first draw.
        InkFontCenter.shared.registerAllCustomFonts()

        model.handler = self
        model.showsGlobe = needsInputModeSwitchKey

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

        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        model.loadDictionaryIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        InkSettings.shared.reload()
        InkFontCenter.shared.reloadFromDefaults()
        model.showsGlobe = needsInputModeSwitchKey
        model.reloadFromSettings()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let constraint = heightConstraint,
           abs(constraint.constant - KeyboardMetrics.totalHeight) > 0.5 {
            constraint.constant = KeyboardMetrics.totalHeight
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Nothing to mirror: the T9 buffer belongs to this keyboard only.
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
}
