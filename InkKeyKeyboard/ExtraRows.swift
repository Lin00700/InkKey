//
//  ExtraRows.swift
//  InkKeyKeyboard
//
//  The two thin rows that sit around the candidate strip:
//    - SentenceReferenceRow: 中文语句 | 英文翻译参考 | 🔊
//    - InlineSyllableStrip: 拼音音节 chips for disambiguating the 9-key digits
//

import SwiftUI

// MARK: - Sentence reference

struct SentenceReferenceRow: View {
    let sentence: InkSentence
    let palette: InkPalette
    let fonts: InkFontCenter
    let onChinese: () -> Void
    let onEnglish: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("句")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.paper)
                .frame(width: 17, height: 17)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.seal.opacity(0.88))
                )

            Button(action: onChinese) {
                Text(sentence.chinese)
                    .font(fonts.swiftUIFont(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.secondaryText.opacity(0.8))

            Button(action: onEnglish) {
                HStack(spacing: 3) {
                    Text(sentence.pendingDisplay)
                        .font(fonts.swiftUIFont(size: 12, weight: .regular))
                        .foregroundStyle(sentence.isOnline ? palette.inkSoft : palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: sentence.isOnline ? "globe" : "internaldrive")
                        .font(.system(size: 8))
                        .foregroundStyle(palette.secondaryText.opacity(0.75))
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onSpeak) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.seal.opacity(0.9))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(sentence.english.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.candidateBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.divider.opacity(0.7), lineWidth: 0.6)
        )
    }
}

private extension InkSentence {
    var pendingDisplay: String {
        if english.isEmpty { return "翻译中…" }
        return isPending ? "\(english) …" : english
    }
}

// MARK: - Pinyin syllable chips

struct InlineSyllableStrip: View {
    let options: [InkSyllableOption]
    let locked: [String]
    let palette: InkPalette
    let fonts: InkFontCenter
    let onSelect: (InkSyllableOption) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                if !locked.isEmpty {
                    Button(action: onClear) {
                        HStack(spacing: 3) {
                            Text(locked.joined(separator: " "))
                                .font(fonts.swiftUIFont(size: 11, weight: .semibold))
                                .foregroundStyle(palette.seal)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(palette.seal.opacity(0.10))
                        )
                        .overlay(
                            Capsule().stroke(palette.seal.opacity(0.38), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)

                    Text("音节")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.secondaryText.opacity(0.8))
                        .padding(.trailing, 1)
                }

                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option.text)
                            .font(fonts.swiftUIFont(size: 12, weight: option.isExact ? .semibold : .regular))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(option.isExact
                                               ? palette.keyFill
                                               : palette.keyFill.opacity(0.66))
                            )
                            .overlay(
                                Capsule().stroke(option.isExact
                                                 ? palette.seal.opacity(0.45)
                                                 : palette.divider.opacity(0.8),
                                                 lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
