//
//  InkFont.swift
//  InkKey / InkKeyKeyboard
//
//  Font swapping for the keyboard: four built-in presets plus user imported
//  .ttf/.otf files that live in the App Group container and are registered at
//  runtime with CoreText in BOTH the app and the keyboard extension.
//

import CoreText
import Foundation
import SwiftUI
import UIKit

// MARK: - Built-in presets

enum InkFontPreset: String, CaseIterable, Identifiable, Codable {
    case system
    case songti
    case kaiti
    case rounded
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统默认"
        case .songti: return "水墨宋体"
        case .kaiti: return "楷体手写"
        case .rounded: return "圆润黑体"
        case .mono: return "等宽极客"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "PingFang SC · 清晰稳当"
        case .songti: return "Songti SC · 落笔如墨"
        case .kaiti: return "Kaiti SC · 手写气息"
        case .rounded: return "SF Rounded · 柔和"
        case .mono: return "SF Mono · 极客等宽"
        }
    }

    /// PostScript names tried in order; iOS ships different subsets per device
    /// and OS version, so a missing name simply falls through to the next one.
    var postScriptNames: [String] {
        switch self {
        case .system: return []
        case .songti: return ["STSongti-SC-Regular", "Songti SC", "STSong", "SongtiSC-Regular"]
        case .kaiti: return ["STKaitiSC-Regular", "Kaiti SC", "KaitiSC-Regular", "STKaiti"]
        case .rounded: return []
        case .mono: return []
        }
    }

    /// Family names used when no PostScript name on this OS matches.
    var familyNames: [String] {
        switch self {
        case .songti: return ["Songti SC", "Songti TC"]
        case .kaiti: return ["Kaiti SC", "STKaiti", "Kaiti TC"]
        default: return []
        }
    }

    var fallbackDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .songti, .kaiti: return .serif
        case .mono: return .monospaced
        case .rounded: return .rounded
        case .system: return nil
        }
    }
}

// MARK: - Imported fonts

struct InkCustomFont: Codable, Identifiable, Hashable {
    var file: String
    var displayName: String
    var postScriptName: String
    var addedAt: Date

    var id: String { file }
}

enum InkFontError: LocalizedError {
    case unsupportedType
    case tooLarge
    case unreadable
    case noContainer

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return "只支持 .ttf / .otf / .ttc 字体文件"
        case .tooLarge: return "字体文件太大了（上限 32MB）"
        case .unreadable: return "这个字体文件读不出来，换一个试试"
        case .noContainer: return "App Group 共享目录不可用，请检查签名时的 App Group 勾选"
        }
    }
}

// MARK: - Font center

/// Single source of truth for every font the keyboard draws with.
/// Lives in the shared sources so the app and the extension use identical logic.
final class InkFontCenter: ObservableObject {
    static let shared = InkFontCenter()

    @Published private(set) var preset: InkFontPreset
    @Published private(set) var customFonts: [InkCustomFont]
    @Published private(set) var activeCustomFile: String?
    @Published var lastError: String?

    private var registeredFiles: Set<String> = []

    private init() {
        let d = InkShared.defaults
        preset = InkFontPreset(rawValue: d.string(forKey: InkKeyName.fontPreset) ?? "") ?? .system
        if let data = d.data(forKey: InkKeyName.fontCustomList),
           let list = try? JSONDecoder().decode([InkCustomFont].self, from: data) {
            customFonts = list
        } else {
            customFonts = []
        }
        activeCustomFile = d.string(forKey: InkKeyName.fontActiveCustom)
        registerAllCustomFonts()
    }

    // MARK: Selection

    var activeCustomFont: InkCustomFont? {
        guard let file = activeCustomFile else { return nil }
        return customFonts.first { $0.file == file }
    }

    var activeTitle: String {
        if let custom = activeCustomFont { return custom.displayName }
        return preset.title
    }

    /// True when the user picked a preset that this iOS build does not ship.
    var activePresetIsMissing: Bool {
        guard activeCustomFont == nil, !preset.postScriptNames.isEmpty else { return false }
        return resolvedPostScriptName(for: preset) == nil
    }

    func selectPreset(_ value: InkFontPreset) {
        preset = value
        activeCustomFile = nil
        save()
        objectWillChange.send()
    }

    func selectCustom(_ font: InkCustomFont) {
        activeCustomFile = font.file
        save()
        objectWillChange.send()
    }

    func clearCustomSelection() {
        activeCustomFile = nil
        save()
        objectWillChange.send()
    }

    // MARK: Resolving a UIFont

    func font(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if let custom = activeCustomFont {
            if let f = UIFont(name: custom.postScriptName, size: size) {
                return f
            }
            // the font may have been re-signed away — try to register it again
            if let ps = registerFontFile(custom.file), let f = UIFont(name: ps, size: size) {
                return f
            }
        }
        if let name = resolvedPostScriptName(for: preset), let f = UIFont(name: name, size: size) {
            return f
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let design = preset.fallbackDesign, let descriptor = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    func swiftUIFont(size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        Font(font(size: size, weight: weight))
    }

    private var presetNameCache: [InkFontPreset: String?] = [:]

    /// Returns the real PostScript name of the first available face of a preset.
    func resolvedPostScriptName(for value: InkFontPreset) -> String? {
        if let cached = presetNameCache[value] { return cached }
        var found: String? = nil
        for name in value.postScriptNames {
            if let font = UIFont(name: name, size: 12) {
                found = font.fontName
                break
            }
        }
        if found == nil {
            for family in value.familyNames {
                let descriptor = UIFontDescriptor(fontAttributes: [
                    UIFontDescriptor.AttributeName.family: family
                ])
                let font = UIFont(descriptor: descriptor, size: 12)
                if font.familyName == family {
                    found = font.fontName
                    break
                }
            }
        }
        presetNameCache[value] = found
        return found
    }

    // MARK: Registering custom fonts

    func registerAllCustomFonts() {
        for font in customFonts {
            _ = registerFontFile(font.file)
        }
    }

    @discardableResult
    func registerFontFile(_ fileName: String) -> String? {
        if registeredFiles.contains(fileName), let cached = postScriptCache[fileName] {
            return cached
        }
        guard let dir = InkShared.fontsDirectory else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok {
            // Already registered in this process is fine and expected on reloads.
            let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) }
            if code != 105 { // kCTFontManagerErrorAlreadyRegistered
                lastError = "字体注册失败（\(code ?? -1)）"
            }
        }

        var name: String? = nil
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let descriptor = descriptors.first,
           let ps = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
            name = ps
        }
        if let name {
            registeredFiles.insert(fileName)
            postScriptCache[fileName] = name
        }
        return name
    }

    private var postScriptCache: [String: String] = [:]

    // MARK: Importing / deleting

    @discardableResult
    func importFont(at url: URL) throws -> InkCustomFont {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc", "otc"].contains(ext) else { throw InkFontError.unsupportedType }
        guard let dir = InkShared.fontsDirectory else { throw InkFontError.noContainer }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 32 * 1024 * 1024 else { throw InkFontError.tooLarge }

        let rawName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = rawName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\u{0}", with: "")
        let unique = "\(safeName)-\(UUID().uuidString.prefix(6)).\(ext)"
        let destination = dir.appendingPathComponent(unique)
        try data.write(to: destination, options: .atomic)

        guard let psName = registerFontFile(unique) else {
            try? FileManager.default.removeItem(at: destination)
            throw InkFontError.unreadable
        }

        let font = InkCustomFont(
            file: unique,
            displayName: safeName.isEmpty ? "自定义字体" : safeName,
            postScriptName: psName,
            addedAt: Date()
        )
        customFonts.append(font)
        activeCustomFile = unique
        save()
        objectWillChange.send()
        return font
    }

    func delete(_ font: InkCustomFont) {
        if let dir = InkShared.fontsDirectory {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(font.file))
        }
        customFonts.removeAll { $0.file == font.file }
        registeredFiles.remove(font.file)
        postScriptCache[font.file] = nil
        if activeCustomFile == font.file { activeCustomFile = nil }
        save()
        objectWillChange.send()
    }

    /// Re-reads the selection another process may have written.
    func reloadFromDefaults() {
        let d = InkShared.defaults
        let p = InkFontPreset(rawValue: d.string(forKey: InkKeyName.fontPreset) ?? "") ?? .system
        var list: [InkCustomFont] = []
        if let data = d.data(forKey: InkKeyName.fontCustomList),
           let decoded = try? JSONDecoder().decode([InkCustomFont].self, from: data) {
            list = decoded
        }
        let active = d.string(forKey: InkKeyName.fontActiveCustom)
        if p != preset || list != customFonts || active != activeCustomFile {
            preset = p
            customFonts = list
            activeCustomFile = active
            registerAllCustomFonts()
            objectWillChange.send()
        }
    }

    private func save() {
        let d = InkShared.defaults
        d.set(preset.rawValue, forKey: InkKeyName.fontPreset)
        if let data = try? JSONEncoder().encode(customFonts) {
            d.set(data, forKey: InkKeyName.fontCustomList)
        }
        d.set(activeCustomFile, forKey: InkKeyName.fontActiveCustom)
    }
}
