//
//  SetupView.swift
//  InkKey
//
//  First tab: how to switch the keyboard on, plus a scratch pad to try it.
//

import SwiftUI
import UIKit

struct SetupView: View {
    @ObservedObject private var settings = InkSettings.shared
    @ObservedObject private var fonts = InkFontCenter.shared
    @ObservedObject private var vocabulary = VocabularyStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("ink.check.added", store: InkShared.defaults) private var keyboardAdded = false
    @AppStorage("ink.check.access", store: InkShared.defaults) private var fullAccess = false

    @State private var testText = ""
    @FocusState private var testFocused: Bool

    var body: some View {
        let palette = InkPalette.resolve(settings.theme, scheme: colorScheme)
        ScrollView {
            VStack(spacing: 18) {
                header(palette)
                stepsCard(palette)
                testCard(palette)
                featureGrid(palette)
                footer(palette)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(InkBackground(palette: palette))
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Header

    private func header(_ palette: InkPalette) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("InkKey")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("水墨双语九宫格输入法")
                    .font(fonts.swiftUIFont(size: 14, weight: .regular))
                    .foregroundStyle(palette.inkSoft)
                    .tracking(1.5)
                InkUnderline(palette: palette, width: 150)
            }
            Spacer()
            InkSeal(palette: palette, text: "墨", size: 44)
        }
        .padding(.top, 4)
    }

    // MARK: Enable steps

    private func stepsCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                InkSectionLabel(text: "三步启用", palette: palette)
                stepRow(palette, index: 1, title: "添加键盘",
                        detail: "设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → InkKey",
                        isOn: $keyboardAdded)
                InkDivider(palette: palette)
                stepRow(palette, index: 2, title: "允许完全访问",
                        detail: "同页点开 InkKey，打开「允许完全访问」——发音、生词本与字体共享都靠它",
                        isOn: $fullAccess)
                InkDivider(palette: palette)
                stepRow(palette, index: 3, title: "开始打字",
                        detail: "在下面试打，或长按地球键切到 InkKey",
                        isOn: .constant(true))

                HStack(spacing: 10) {
                    Button {
                        openSettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gearshape")
                            .font(fonts.swiftUIFont(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.paper)
                    .background(Capsule().fill(palette.ink))
                    .overlay(Capsule().stroke(palette.ink.opacity(0.5), lineWidth: 0.5))

                    Button {
                        testFocused = true
                    } label: {
                        Label("试打一下", systemImage: "hand.tap")
                            .font(fonts.swiftUIFont(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.ink)
                    .background(Capsule().stroke(palette.ink.opacity(0.35), lineWidth: 0.8))
                }
                .padding(.top, 2)

                if InkFontCenter.shared.activeCustomFont != nil || InkFontCenter.shared.preset != .system {
                    Text("当前字体：\(InkFontCenter.shared.activeTitle)")
                        .font(fonts.swiftUIFont(size: 11))
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private func stepRow(_ palette: InkPalette, index: Int, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(palette.ink.opacity(0.25), lineWidth: 0.8)
                    .frame(width: 24, height: 24)
                Text("\(index)")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.seal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(fonts.swiftUIFont(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink)
                Text(detail)
                    .font(fonts.swiftUIFont(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(palette.seal)
                .disabled(index == 3)
        }
    }

    // MARK: Test pad

    private func testCard(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    InkSectionLabel(text: "试打", palette: palette)
                    Spacer()
                    if testFocused {
                        Button("收起键盘") { testFocused = false }
                            .font(fonts.swiftUIFont(size: 11))
                            .foregroundStyle(palette.seal)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if testText.isEmpty {
                        Text("在这里输入…长按地球键切换到 InkKey")
                            .font(fonts.swiftUIFont(size: 15))
                            .foregroundStyle(palette.secondaryText.opacity(0.8))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextField("", text: $testText, axis: .vertical)
                        .font(fonts.swiftUIFont(size: 18))
                        .foregroundStyle(palette.ink)
                        .focused($testFocused)
                        .lineLimit(3...6)
                        .padding(10)
                        .textFieldStyle(.plain)
                }
                .frame(minHeight: 96, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.paper.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.divider, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
                if !testText.isEmpty {
                    HStack {
                        Text("已输入 \(testText.count) 字")
                            .font(fonts.swiftUIFont(size: 11))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Button("清空") { testText = "" }
                            .font(fonts.swiftUIFont(size: 11))
                            .foregroundStyle(palette.seal)
                    }
                }
            }
        }
    }

    // MARK: Feature grid

    private func featureGrid(_ palette: InkPalette) -> some View {
        let items: [FeatureItem] = [
            FeatureItem(id: 0, icon: "character.book.closed", title: "双语对照",
                        detail: "上行中文、下行英文；打英文时下行给中文释义，点哪行上哪行"),
            FeatureItem(id: 1, icon: "speaker.wave.2", title: "点读即学",
                        detail: "每个候选都有小喇叭，点一下就朗读并自动记进生词本"),
            FeatureItem(id: 2, icon: "textformat", title: "字体随意换",
                        detail: "宋体、楷体、圆体、等宽，还能导入自己的 ttf / otf"),
            FeatureItem(id: 3, icon: "bolt.horizontal", title: "离线词库 + 手写",
                        detail: "中文 4.1 万条、英文 9000 词，另有 6,708 字离线手写，断网可用")
        ]
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                InkCard(palette: palette, padding: 13) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(palette.seal)
                        Text(item.title)
                            .font(fonts.swiftUIFont(size: 14, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Text(item.detail)
                            .font(fonts.swiftUIFont(size: 11))
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func footer(_ palette: InkPalette) -> some View {
        VStack(spacing: 6) {
            Text("词库 \(InkDictionaryStore.shared.isLoaded ? "\(InkDictionaryStore.shared.totalCount) 条" : "内置 · 加载中")　·　生词本 \(vocabulary.count) 词")
                .font(fonts.swiftUIFont(size: 11))
                .foregroundStyle(palette.secondaryText)
            Text(InkShared.hasAppGroup ? "App Group 已连接" : "App Group 未连接（配置与生词本会退回本机存储）")
                .font(fonts.swiftUIFont(size: 10))
                .foregroundStyle(palette.secondaryText.opacity(0.8))
            Text("InkKey 1.0.0 · iOS 17+")
                .font(fonts.swiftUIFont(size: 10))
                .foregroundStyle(palette.secondaryText.opacity(0.7))
        }
        .padding(.top, 6)
    }

    // MARK: Actions

    private func openSettings() {
        let keyboardURL = URL(string: "App-Prefs:root=General&path=Keyboard/KEYBOARDS")
        if let keyboardURL, UIApplication.shared.canOpenURL(keyboardURL) {
            UIApplication.shared.open(keyboardURL) { ok in
                if !ok, let fallback = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(fallback)
                }
            }
        } else if let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback)
        }
    }
}

private struct FeatureItem: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let detail: String
}

#Preview {
    SetupView()
}
