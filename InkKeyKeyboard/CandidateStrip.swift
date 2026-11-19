//
//  CandidateStrip.swift
//  InkKeyKeyboard
//
//  The bilingual two-line candidate strip.  Every candidate is a pair:
//    Chinese mode : 中文词  /  English translation   (tap either line)
//    English mode : word    /  中文释义              (tap either line)
//  A composed phrase/sentence gets its own 句 tag in front of the word list.
//  The little speaker speaks the English side and files it into 生词本.
//  The trailing chevron closes the keyboard in every mode and page.
//

import SwiftUI

struct CandidateStrip: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject private var fonts = InkFontCenter.shared
    let palette: InkPalette

    var body: some View {
        HStack(spacing: 6) {
            modeBadge

            if model.isLoading {
                message("词库加载中…")
            } else if model.candidates.isEmpty {
                message(emptyHint)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(model.candidates) { candidate in
                            CandidateCell(
                                candidate: candidate,
                                isFirst: candidate.id == model.candidates.first?.id,
                                palette: palette,
                                fonts: fonts,
                                onPrimary: { model.insertCandidate(candidate, part: .primary) },
                                onSecondary: { model.insertCandidate(candidate, part: .secondary) },
                                onSpeak: { model.speak(candidate) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            dismissButton
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
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

    private var emptyHint: String {
        if model.mode == .chinese {
            return "九宫格拼音 · 例如 96636 → 我们"
        }
        return "26 键英文 · 输入字母看补全、音标与释义"
    }

    private var modeBadge: some View {
        Button {
            model.toggleMode()
        } label: {
            VStack(spacing: 1) {
                Text(model.mode == .chinese ? "中" : "EN")
                    .font(fonts.swiftUIFont(size: 15, weight: .semibold))
                    .foregroundStyle(palette.seal)
                Text(bufferEcho)
                    .font(fonts.swiftUIFont(size: 9, weight: .regular))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 44)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.keyFill.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
    }

    private var bufferEcho: String {
        if model.mode == .english {
            return model.buffer.isEmpty ? "26键" : model.buffer
        }
        let locked = model.lockedSyllables.joined(separator: " ")
        if locked.isEmpty {
            return model.buffer.isEmpty ? "拼音" : model.buffer
        }
        return locked + " " + model.buffer
    }

    /// Always present, in every mode and page: closes the keyboard.
    private var dismissButton: some View {
        Button {
            model.dismissKeyboard()
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.inkSoft)
                .frame(width: 36, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.keyFill.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.divider.opacity(0.85), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收起键盘")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(fonts.swiftUIFont(size: 12, weight: .regular))
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One candidate pair

struct CandidateCell: View {
    let candidate: InkCandidate
    let isFirst: Bool
    let palette: InkPalette
    let fonts: InkFontCenter
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onPrimary) {
                VStack(alignment: .leading, spacing: 0) {
                    if !candidate.phonetic.isEmpty {
                        Text(candidate.phonetic)
                            .font(fonts.swiftUIFont(size: 9, weight: .regular))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                    HStack(spacing: 3) {
                        if candidate.isPhrase {
                            Text("句")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(palette.paper)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(palette.seal.opacity(0.85))
                                )
                        }
                        Text(candidate.primary)
                            .font(fonts.swiftUIFont(size: candidate.isPhrase ? 16 : (candidate.isChinese ? 21 : 19),
                                                    weight: .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button(action: onSecondary) {
                    Text(candidate.secondary)
                        .font(fonts.swiftUIFont(size: 11, weight: .regular))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !candidate.speakText.isEmpty {
                    Button(action: onSpeak) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.seal.opacity(0.85))
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 80, idealWidth: 104, maxWidth: candidate.isPhrase ? 220 : 168, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isFirst ? palette.keyFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isFirst ? palette.seal.opacity(0.35) : palette.divider.opacity(0.0), lineWidth: 0.8)
        )
    }
}
