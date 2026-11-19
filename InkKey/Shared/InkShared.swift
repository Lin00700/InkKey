//
//  InkShared.swift
//  InkKey / InkKeyKeyboard
//
//  Shared constants, settings and the ink-wash palette used by both targets.
//

import SwiftUI
import UIKit

// MARK: - App Group plumbing

enum InkShared {
    static let appGroupID = "group.com.lin.inkkey"
    static let keyboardBundleID = "com.lin.inkkey.keyboard"
    static let dictionaryFileName = "dictionary"
    static let vocabularyFileName = "vocabulary.json"
    static let fontsFolderName = "Fonts"

    /// App Group defaults with a graceful fallback so the app still works when
    /// the group container is missing (e.g. an old build without the entitlement).
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroupID) ?? .standard

    static var hasAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static var containerURL: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        // Fallback: the app's own Application Support directory (and the
        // extension's cache directory) so nothing crashes, features just
        // stop being shared.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Creates (once) and returns a directory inside the shared container.
    static func directory(named name: String) -> URL? {
        guard let base = containerURL else { return nil }
        let url = base.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static var fontsDirectory: URL? { directory(named: fontsFolderName) }
}

// MARK: - Settings keys

enum InkKeyName {
    static let keyboardMode = "ink.settings.mode"
    static let theme = "ink.settings.theme"
    static let accent = "ink.settings.accent"
    static let speechRate = "ink.settings.speechRate"
    static let haptics = "ink.settings.haptics"
    static let fontPreset = "ink.settings.fontPreset"
    static let fontCustomList = "ink.settings.fontCustomList"
    static let fontActiveCustom = "ink.settings.fontActiveCustom"
    static let didFinishSetup = "ink.settings.didFinishSetup"
    static let translateOnline = "ink.settings.translateOnline"
    static let translateEndpoint = "ink.settings.translateEndpoint"
    static let translateModel = "ink.settings.translateModel"
    static let translateKey = "ink.settings.translateKey"
    static let userFrequency = "ink.settings.userFrequency"
}

// MARK: - Small value types

enum InkMode: String, CaseIterable, Identifiable, Codable {
    case chinese
    case english

    var id: String { rawValue }
    var title: String { self == .chinese ? "中文九宫格" : "英文 26 键" }
    var shortTitle: String { self == .chinese ? "中文" : "English" }
    var toggled: InkMode { self == .chinese ? .english : .chinese }
}

enum InkThemeMode: String, CaseIterable, Identifiable, Codable {
    case paper
    case ink
    case system

    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: return "宣纸浅色"
        case .ink: return "墨夜深色"
        case .system: return "跟随系统"
        }
    }
}

enum InkAccent: String, CaseIterable, Identifiable, Codable {
    case us
    case gb

    var id: String { rawValue }
    var language: String { self == .us ? "en-US" : "en-GB" }
    var title: String { self == .us ? "美式发音 en-US" : "英式发音 en-GB" }
}

// MARK: - Settings store (shared by app and keyboard through the App Group)

final class InkSettings: ObservableObject {
    static let shared = InkSettings()

    @Published var mode: InkMode {
        didSet { InkShared.defaults.set(mode.rawValue, forKey: InkKeyName.keyboardMode) }
    }
    @Published var theme: InkThemeMode {
        didSet { InkShared.defaults.set(theme.rawValue, forKey: InkKeyName.theme) }
    }
    @Published var accent: InkAccent {
        didSet { InkShared.defaults.set(accent.rawValue, forKey: InkKeyName.accent) }
    }
    @Published var speechRate: Double {
        didSet { InkShared.defaults.set(speechRate, forKey: InkKeyName.speechRate) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { InkShared.defaults.set(hapticsEnabled, forKey: InkKeyName.haptics) }
    }
    /// Sentence reference: ask a translation endpoint while typing.
    @Published var translateOnline: Bool {
        didSet { InkShared.defaults.set(translateOnline, forKey: InkKeyName.translateOnline) }
    }
    /// Empty means the built-in zero-key Google endpoint is used.
    @Published var translateEndpoint: String {
        didSet { InkShared.defaults.set(translateEndpoint, forKey: InkKeyName.translateEndpoint) }
    }
    @Published var translateModel: String {
        didSet { InkShared.defaults.set(translateModel, forKey: InkKeyName.translateModel) }
    }
    @Published var translateKey: String {
        didSet { InkShared.defaults.set(translateKey, forKey: InkKeyName.translateKey) }
    }

    private init() {
        let d = InkShared.defaults
        mode = InkMode(rawValue: d.string(forKey: InkKeyName.keyboardMode) ?? "") ?? .chinese
        theme = InkThemeMode(rawValue: d.string(forKey: InkKeyName.theme) ?? "") ?? .paper
        accent = InkAccent(rawValue: d.string(forKey: InkKeyName.accent) ?? "") ?? .us
        let storedRate = d.object(forKey: InkKeyName.speechRate) as? Double
        speechRate = storedRate ?? 0.45
        if d.object(forKey: InkKeyName.haptics) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = d.bool(forKey: InkKeyName.haptics)
        }
        if d.object(forKey: InkKeyName.translateOnline) == nil {
            translateOnline = true
        } else {
            translateOnline = d.bool(forKey: InkKeyName.translateOnline)
        }
        translateEndpoint = d.string(forKey: InkKeyName.translateEndpoint) ?? ""
        let storedModel = d.string(forKey: InkKeyName.translateModel) ?? ""
        translateModel = storedModel.isEmpty ? "gpt-4o-mini" : storedModel
        translateKey = d.string(forKey: InkKeyName.translateKey) ?? ""
    }

    /// Re-reads values another process may have changed (keyboard -> app).
    func reload() {
        let d = InkShared.defaults
        let m = InkMode(rawValue: d.string(forKey: InkKeyName.keyboardMode) ?? "") ?? mode
        let t = InkThemeMode(rawValue: d.string(forKey: InkKeyName.theme) ?? "") ?? theme
        let a = InkAccent(rawValue: d.string(forKey: InkKeyName.accent) ?? "") ?? accent
        let r = (d.object(forKey: InkKeyName.speechRate) as? Double) ?? speechRate
        let h = (d.object(forKey: InkKeyName.haptics) as? Bool) ?? hapticsEnabled
        if m != mode { mode = m }
        if t != theme { theme = t }
        if a != accent { accent = a }
        if abs(r - speechRate) > 0.0001 { speechRate = r }
        if h != hapticsEnabled { hapticsEnabled = h }

        let online = (d.object(forKey: InkKeyName.translateOnline) as? Bool) ?? translateOnline
        let endpoint = d.string(forKey: InkKeyName.translateEndpoint) ?? ""
        let model = d.string(forKey: InkKeyName.translateModel) ?? ""
        let key = d.string(forKey: InkKeyName.translateKey) ?? ""
        if online != translateOnline { translateOnline = online }
        if endpoint != translateEndpoint { translateEndpoint = endpoint }
        let modelResolved = model.isEmpty ? "gpt-4o-mini" : model
        if modelResolved != translateModel { translateModel = modelResolved }
        if key != translateKey { translateKey = key }
    }

    /// True when either a custom endpoint or the built-in one may be used.
    var translationAvailable: Bool { translateOnline }
}

// MARK: - Palette

struct InkPalette {
    let isDark: Bool
    let paper: Color
    let paperDeep: Color
    let ink: Color
    let inkSoft: Color
    let seal: Color
    let keyFill: Color
    let keyFillPressed: Color
    let keyStroke: Color
    let keyText: Color
    let candidateBackground: Color
    let secondaryText: Color
    let divider: Color

    static let paperTheme = InkPalette(
        isDark: false,
        paper: Color(red: 0.968, green: 0.953, blue: 0.925),
        paperDeep: Color(red: 0.925, green: 0.902, blue: 0.858),
        ink: Color(red: 0.129, green: 0.125, blue: 0.118),
        inkSoft: Color(red: 0.353, green: 0.341, blue: 0.318),
        seal: Color(red: 0.647, green: 0.168, blue: 0.145),
        keyFill: Color(red: 0.996, green: 0.992, blue: 0.984),
        keyFillPressed: Color(red: 0.898, green: 0.882, blue: 0.851),
        keyStroke: Color(red: 0.788, green: 0.769, blue: 0.729),
        keyText: Color(red: 0.145, green: 0.141, blue: 0.133),
        candidateBackground: Color(red: 0.945, green: 0.929, blue: 0.898),
        secondaryText: Color(red: 0.435, green: 0.416, blue: 0.384),
        divider: Color(red: 0.835, green: 0.816, blue: 0.780)
    )

    static let inkTheme = InkPalette(
        isDark: true,
        paper: Color(red: 0.086, green: 0.090, blue: 0.098),
        paperDeep: Color(red: 0.129, green: 0.133, blue: 0.145),
        ink: Color(red: 0.929, green: 0.918, blue: 0.886),
        inkSoft: Color(red: 0.686, green: 0.671, blue: 0.631),
        seal: Color(red: 0.780, green: 0.286, blue: 0.243),
        keyFill: Color(red: 0.196, green: 0.204, blue: 0.216),
        keyFillPressed: Color(red: 0.267, green: 0.275, blue: 0.290),
        keyStroke: Color(red: 0.290, green: 0.298, blue: 0.314),
        keyText: Color(red: 0.937, green: 0.929, blue: 0.906),
        candidateBackground: Color(red: 0.118, green: 0.122, blue: 0.133),
        secondaryText: Color(red: 0.639, green: 0.627, blue: 0.596),
        divider: Color(red: 0.263, green: 0.271, blue: 0.286)
    )

    static func resolve(_ mode: InkThemeMode, scheme: ColorScheme) -> InkPalette {
        switch mode {
        case .paper: return .paperTheme
        case .ink: return .inkTheme
        case .system: return scheme == .dark ? .inkTheme : .paperTheme
        }
    }
}
