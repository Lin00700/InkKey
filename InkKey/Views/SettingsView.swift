//
//  SettingsView.swift
//  InkKey
//
//  设置: theme, font swapping (presets + imported ttf/otf), speech, haptics,
//  default mode and the shared-store diagnostics.
//

import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = InkSettings.shared
    @ObservedObject private var fonts = InkFontCenter.shared
    @ObservedObject private var store = VocabularyStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showImporter = false
    @State private var alertText: String?
    @State private var confirmReset = false

    private static var fontContentTypes: [UTType] {
        var types: [UTType] = [.font]
        for ext in ["ttf", "otf", "ttc", "otc"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    var body: some View {
        let palette = InkPalette.resolve(settings.theme, scheme: colorScheme)
        ScrollView {
            VStack(spacing: 16) {
                header(palette)
                appearanceCard(palette)
                fontCard(palette)
                speechCard(palette)
                keyboardCard(palette)
                aboutCard(palette)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(InkBackground(palette: palette))
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.fontContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert("字体", isPresented: Binding(
            get: { alertText != nil },
            set: { if !$0 { alertText = nil } }
        )) {
            Button("好", role: .cancel) { alertText = nil }
        } message: {
            Text(alertText ?? "")
        }
        .alert("清空生词本？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.removeAll() }
        } message: {
            Text("会删除全部 \(store.count) 个词，无法恢复。")
        }
    }

    // MARK: Header

    private func header(_ palette: InkPalette) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("设置")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("改完自动同步给键盘")
                    .font(fonts.swiftUIFont(size: 12))
                    .foregroundStyle(palette.secondaryText)
                InkUnderline(palette: palette, width: 96)
            }
            Spacer()
        }
    }

    // MARK: Appearance

    private func appearanceCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                InkSectionLabel(text: "外观", palette: palette)
                Picker("主题", selection: $settings.theme) {
                    ForEach(InkThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: Fonts

    private func fontCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                InkSectionLabel(text: "键盘字体", palette: palette)

                Text("永字八法 InkKey 2026")
                    .font(fonts.swiftUIFont(size: 24, weight: .regular))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.paper.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.8)
                    )

                ForEach(InkFontPreset.allCases) { preset in
                    presetRow(preset, palette: palette)
                }

                InkDivider(palette: palette)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自定义字体")
                            .font(fonts.swiftUIFont(size: 14, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Text("导入 .ttf / .otf / .ttc，只在按键与候选里使用")
                            .font(fonts.swiftUIFont(size: 10))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                            .font(fonts.swiftUIFont(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.paper)
                    .background(Capsule().fill(palette.ink))
                }

                if fonts.customFonts.isEmpty {
                    Text("还没有导入字体。可以从「文件」里挑一个字体文件。")
                        .font(fonts.swiftUIFont(size: 11))
                        .foregroundStyle(palette.secondaryText)
                } else {
                    ForEach(fonts.customFonts) { font in
                        customRow(font, palette: palette)
                    }
                }

                if InkFontCenter.shared.activePresetIsMissing {
                    Text("当前系统没有内置「\(fonts.preset.title)」，已自动回退到相近字体。")
                        .font(fonts.swiftUIFont(size: 10))
                        .foregroundStyle(palette.seal.opacity(0.85))
                }

                Text("字体保存在 App Group 的 Fonts 目录，键盘切走再切回来即可生效。")
                    .font(fonts.swiftUIFont(size: 10))
                    .foregroundStyle(palette.secondaryText.opacity(0.85))
            }
        }
    }

    private func presetRow(_ preset: InkFontPreset, palette: InkPalette) -> some View {
        let isActive = fonts.activeCustomFont == nil && fonts.preset == preset
        return Button {
            fonts.selectPreset(preset)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(fonts.swiftUIFont(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(palette.ink)
                    Text(preset.subtitle)
                        .font(fonts.swiftUIFont(size: 10))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Text("永Aa")
                    .font(fontForPreview(preset))
                    .foregroundStyle(palette.inkSoft)
                if isActive {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.seal)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fontForPreview(_ preset: InkFontPreset) -> Font {
        switch preset {
        case .system, .rounded, .mono, .songti, .kaiti:
            if let name = fonts.resolvedPostScriptName(for: preset), let ui = UIFont(name: name, size: 15) {
                return Font(ui)
            }
            let base = UIFont.systemFont(ofSize: 15)
            if let design = preset.fallbackDesign, let descriptor = base.fontDescriptor.withDesign(design) {
                return Font(UIFont(descriptor: descriptor, size: 15))
            }
            return Font(base)
        }
    }

    private func customRow(_ font: InkCustomFont, palette: InkPalette) -> some View {
        let isActive = fonts.activeCustomFile == font.file
        return HStack(spacing: 10) {
            Button {
                fonts.selectCustom(font)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(font.displayName)
                            .font(.custom(font.postScriptName, size: 14))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(font.postScriptName)
                            .font(.system(size: 9))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.seal)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                fonts.delete(font)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let font = try fonts.importFont(at: url)
                alertText = "已导入「\(font.displayName)」，键盘下次出现时就会用上。"
            } catch {
                alertText = error.localizedDescription
            }
        case .failure(let error):
            alertText = error.localizedDescription
        }
    }

    // MARK: Speech

    private func speechCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                InkSectionLabel(text: "发音", palette: palette)
                Picker("口音", selection: $settings.accent) {
                    ForEach(InkAccent.allCases) { accent in
                        Text(accent.title).tag(accent)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("语速")
                            .font(fonts.swiftUIFont(size: 13))
                            .foregroundStyle(palette.inkSoft)
                        Spacer()
                        Text(String(format: "%.2f", settings.speechRate))
                            .font(fonts.swiftUIFont(size: 11))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Slider(value: $settings.speechRate, in: 0.2...0.7, step: 0.05)
                        .tint(palette.seal)
                }

                Button {
                    InkSpeech.shared.speak("InkKey, your bilingual keyboard.")
                } label: {
                    Label("试听", systemImage: "play.circle")
                        .font(fonts.swiftUIFont(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.ink)
                .background(Capsule().stroke(palette.ink.opacity(0.28), lineWidth: 0.8))

                Text("键盘里发音需要「允许完全访问」。")
                    .font(fonts.swiftUIFont(size: 10))
                    .foregroundStyle(palette.secondaryText.opacity(0.9))
            }
        }
    }

    // MARK: Keyboard behaviour

    private func keyboardCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                InkSectionLabel(text: "键盘", palette: palette)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按键震动")
                            .font(fonts.swiftUIFont(size: 14))
                            .foregroundStyle(palette.ink)
                        Text("轻触反馈，长按退格连续删除")
                            .font(fonts.swiftUIFont(size: 10))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.hapticsEnabled)
                        .labelsHidden()
                        .tint(palette.seal)
                }

                InkDivider(palette: palette)

                VStack(alignment: .leading, spacing: 6) {
                    Text("默认输入模式")
                        .font(fonts.swiftUIFont(size: 14))
                        .foregroundStyle(palette.ink)
                    Picker("默认输入模式", selection: $settings.mode) {
                        Text("中文九宫格").tag(InkMode.chinese)
                        Text("English T9").tag(InkMode.english)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: About

    private func aboutCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 10) {
                InkSectionLabel(text: "关于", palette: palette)
                infoRow("内置词库", InkDictionaryStore.shared.isLoaded
                        ? "\(InkDictionaryStore.shared.chinese.count) 中文 + \(InkDictionaryStore.shared.english.count) 英文"
                        : "加载中", palette: palette)
                infoRow("生词本", "\(store.count) 词", palette: palette)
                infoRow("App Group", InkShared.hasAppGroup ? "已连接 group.com.lin.inkkey" : "未连接（使用本机存储）", palette: palette)
                infoRow("字体目录", InkShared.hasAppGroup ? "Fonts（共享）" : "本机缓存", palette: palette)
                infoRow("版本", "InkKey 1.0.0 (1)", palette: palette)

                HStack(spacing: 10) {
                    Button {
                        store.reload()
                    } label: {
                        Text("刷新生词本")
                            .font(fonts.swiftUIFont(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.inkSoft)

                    Spacer()

                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text("清空生词本")
                            .font(fonts.swiftUIFont(size: 12))
                            .foregroundStyle(palette.seal)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.entries.isEmpty)
                }
                .padding(.top, 2)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, palette: InkPalette) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(fonts.swiftUIFont(size: 12))
                .foregroundStyle(palette.secondaryText)
            Spacer()
            Text(value)
                .font(fonts.swiftUIFont(size: 12))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    SettingsView()
}
