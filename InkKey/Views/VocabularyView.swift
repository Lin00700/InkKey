//
//  VocabularyView.swift
//  InkKey
//
//  生词本: every word pronounced from the keyboard lands here.
//

import SwiftUI

struct VocabularyView: View {
    @ObservedObject private var settings = InkSettings.shared
    @ObservedObject private var store = VocabularyStore.shared
    @ObservedObject private var fonts = InkFontCenter.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var query = ""
    @State private var showReview = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        let palette = InkPalette.resolve(settings.theme, scheme: colorScheme)
        let results = store.search(query)

        ScrollView {
            VStack(spacing: 14) {
                header(palette)
                searchBar(palette)
                if results.isEmpty {
                    emptyState(palette)
                } else {
                    ForEach(results) { entry in
                        row(entry, palette: palette)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(InkBackground(palette: palette))
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showReview) {
            ReviewView(palette: palette)
        }
        .onAppear { store.reload() }
    }

    private func header(_ palette: InkPalette) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("生词本")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("共 \(store.count) 词 · 键盘上点小喇叭自动收录")
                    .font(fonts.swiftUIFont(size: 12))
                    .foregroundStyle(palette.secondaryText)
                InkUnderline(palette: palette, width: 118)
            }
            Spacer()
            Button {
                showReview = true
            } label: {
                Label("复习", systemImage: "rectangle.on.rectangle.angled")
                    .font(fonts.swiftUIFont(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.paper)
            .background(Capsule().fill(store.entries.isEmpty ? palette.inkSoft : palette.ink))
            .disabled(store.entries.isEmpty)
        }
    }

    private func searchBar(_ palette: InkPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
            TextField("搜索单词、音标或释义", text: $query)
                .font(fonts.swiftUIFont(size: 14))
                .foregroundStyle(palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.keyFill.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.8)
        )
    }

    private func row(_ entry: VocabularyEntry, palette: InkPalette) -> some View {
        InkCard(palette: palette, padding: 13) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(entry.word)
                            .font(fonts.swiftUIFont(size: 19, weight: .medium))
                            .foregroundStyle(palette.ink)
                        if !entry.phonetic.isEmpty {
                            Text(entry.phonetic)
                                .font(fonts.swiftUIFont(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    if !entry.meaning.isEmpty {
                        Text(entry.meaning)
                            .font(fonts.swiftUIFont(size: 12))
                            .foregroundStyle(palette.inkSoft)
                            .lineLimit(2)
                    }
                    Text("\(Self.dateFormatter.string(from: entry.addedAt)) · 朗读 \(entry.timesSpoken) 次")
                        .font(fonts.swiftUIFont(size: 9))
                        .foregroundStyle(palette.secondaryText.opacity(0.8))
                }
                Spacer(minLength: 4)
                Button {
                    InkSpeech.shared.speak(entry.word)
                    store.markSpoken(entry)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.seal)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(palette.paper.opacity(0.8))
                        )
                        .overlay(Circle().stroke(palette.divider, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            InkSpeech.shared.speak(entry.word)
            store.markSpoken(entry)
        }
        .contextMenu {
            Button {
                InkSpeech.shared.speak(entry.word)
            } label: {
                Label("朗读", systemImage: "speaker.wave.2")
            }
            Button(role: .destructive) {
                store.remove(entry)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func emptyState(_ palette: InkPalette) -> some View {
        InkCard(palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    InkSeal(palette: palette, text: "词", size: 26)
                    Text(query.isEmpty ? "还没有生词" : "没有找到")
                        .font(fonts.swiftUIFont(size: 15, weight: .medium))
                        .foregroundStyle(palette.ink)
                }
                Text(query.isEmpty
                     ? "在键盘上打中文或英文，点候选旁边的小喇叭，就会朗读并自动收进这里。"
                     : "换个关键词试试，或者清空搜索框。")
                    .font(fonts.swiftUIFont(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Review

struct ReviewView: View {
    let palette: InkPalette
    @ObservedObject private var store = VocabularyStore.shared
    @ObservedObject private var fonts = InkFontCenter.shared
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [VocabularyEntry] = []
    @State private var index = 0
    @State private var revealed = false

    var body: some View {
        ZStack {
            InkBackground(palette: palette)
            VStack(spacing: 18) {
                HStack {
                    Text("复习")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text(cards.isEmpty ? "0 / 0" : "\(index + 1) / \(cards.count)")
                        .font(fonts.swiftUIFont(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.inkSoft)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(palette.keyFill))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 22)

                if cards.isEmpty {
                    Spacer()
                    Text("生词本是空的")
                        .font(fonts.swiftUIFont(size: 14))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                } else {
                    card
                    controls
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            cards = store.entries.shuffled()
            index = 0
            revealed = false
        }
    }

    private var current: VocabularyEntry? {
        guard !cards.isEmpty else { return nil }
        return cards[min(index, cards.count - 1)]
    }

    private var card: some View {
        InkCard(palette: palette, padding: 22) {
            VStack(spacing: 12) {
                if let entry = current {
                    Text(entry.word)
                        .font(fonts.swiftUIFont(size: 32, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    if !entry.phonetic.isEmpty {
                        Text(entry.phonetic)
                            .font(fonts.swiftUIFont(size: 14))
                            .foregroundStyle(palette.secondaryText)
                    }
                    InkDivider(palette: palette)
                    if revealed {
                        Text(entry.meaning)
                            .font(fonts.swiftUIFont(size: 15))
                            .foregroundStyle(palette.inkSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button {
                            revealed = true
                        } label: {
                            Text("轻点看释义")
                                .font(fonts.swiftUIFont(size: 12))
                                .foregroundStyle(palette.seal)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        InkSpeech.shared.speak(entry.word)
                        store.markSpoken(entry)
                    } label: {
                        Label("朗读", systemImage: "speaker.wave.2.fill")
                            .font(fonts.swiftUIFont(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.ink)
                    .background(Capsule().stroke(palette.ink.opacity(0.3), lineWidth: 0.8))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
        .contentShape(Rectangle())
        .onTapGesture { revealed.toggle() }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                step(-1)
            } label: {
                Label("上一个", systemImage: "chevron.left")
                    .font(fonts.swiftUIFont(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink)
            .background(Capsule().stroke(palette.ink.opacity(0.25), lineWidth: 0.8))

            Button {
                step(1)
            } label: {
                Label("下一个", systemImage: "chevron.right")
                    .font(fonts.swiftUIFont(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.paper)
            .background(Capsule().fill(palette.ink))
        }
    }

    private func step(_ delta: Int) {
        guard !cards.isEmpty else { return }
        index = (index + delta + cards.count) % cards.count
        revealed = false
    }
}
