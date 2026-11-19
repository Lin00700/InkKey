//
//  KeyboardView.swift
//  InkKeyKeyboard
//
//  The keyboard itself.  Two layouts share one frame:
//    - Chinese 9-key: 3x3 T9 grid, punctuation column, function column,
//      bilingual candidate strip, pinyin syllable strip, sentence reference,
//      symbol and number pages.
//    - English 26-key: QWERTY rows with shift, backspace and a return key that
//      carries the host's own label (搜索 / 发送 / 前往 …).
//

import SwiftUI

enum KeyboardMetrics {
    static let portraitHeight: CGFloat = 340
    static let landscapeHeight: CGFloat = 262
    static let candidateHeight: CGFloat = 88
    static let sentenceRowHeight: CGFloat = 30
    static let syllableRowHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 3
    static let gap: CGFloat = 6
}

// MARK: - Root

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject private var settings = InkSettings.shared
    @ObservedObject private var fonts = InkFontCenter.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = InkPalette.resolve(settings.theme, scheme: colorScheme)
        let topHeight = KeyboardMetrics.candidateHeight + model.topExtraHeight
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [palette.paperDeep, palette.paper],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 5) {
                VStack(spacing: KeyboardMetrics.rowSpacing) {
                    if model.showsSentenceRow, let sentence = model.sentence {
                        SentenceReferenceRow(
                            sentence: sentence,
                            palette: palette,
                            fonts: fonts,
                            onChinese: { model.insertSentenceChinese() },
                            onEnglish: { model.insertSentenceEnglish() },
                            onSpeak: { model.speakSentence() }
                        )
                        .frame(height: KeyboardMetrics.sentenceRowHeight)
                    }

                    CandidateStrip(model: model, palette: palette)
                        .frame(maxHeight: .infinity)

                    if model.showsSyllableRow {
                        InlineSyllableStrip(
                            options: model.syllableOptions,
                            locked: model.lockedSyllables,
                            palette: palette,
                            fonts: fonts,
                            onSelect: { model.selectSyllable($0) },
                            onClear: { model.clearSyllableLocks() }
                        )
                        .frame(height: KeyboardMetrics.syllableRowHeight)
                    }
                }
                .frame(height: topHeight)

                KeysArea(model: model, palette: palette)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .padding(.bottom, 6)

            if let toast = model.toast {
                Text(toast)
                    .font(fonts.swiftUIFont(size: 11, weight: .medium))
                    .foregroundStyle(palette.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(palette.ink.opacity(0.86))
                    )
                    .padding(.top, topHeight + 12)
                    .transition(.opacity)
            }
        }
        .frame(height: model.keyboardHeight)
        .background(palette.paper)
    }
}

// MARK: - Keys

struct KeysArea: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject private var fonts = InkFontCenter.shared
    let palette: InkPalette

    private var gap: CGFloat { KeyboardMetrics.gap }

    var body: some View {
        GeometryReader { geo in
            if model.mode == .english {
                EnglishKeysArea(model: model, palette: palette)
            } else {
                chineseLayout(geo)
            }
        }
    }

    // MARK: Chinese 9-key

    private func chineseLayout(_ geo: GeometryProxy) -> some View {
        let width = geo.size.width
        let height = geo.size.height
        let unit = max(28, (width - gap * 4) / 4.76)
        let punctWidth = unit * 0.86
        let functionWidth = unit * 0.90
        let bottomHeight = max(36, (height - gap * 3) * 0.19)
        let rowHeight = max(30, (height - gap * 3 - bottomHeight) / 3)

        return HStack(spacing: gap) {
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    if model.page == .t9 {
                        punctuationColumn(width: punctWidth, height: rowHeight * 3 + gap * 2)
                        t9Grid(unit: unit, rowHeight: rowHeight)
                    } else if model.page == .numbers {
                        numberPad()
                    } else {
                        symbolPad()
                    }
                }
                .frame(height: rowHeight * 3 + gap * 2)

                bottomBar(unit: unit, punctWidth: punctWidth, height: bottomHeight)
                    .frame(height: bottomHeight)
            }

            functionColumn(width: functionWidth, rowHeight: rowHeight, bottomHeight: bottomHeight)
        }
    }

    // MARK: Left punctuation column

    private func punctuationColumn(width: CGFloat, height: CGFloat) -> some View {
        let marks = model.mode == .chinese ? ["，", "。", "？", "！"] : [",", ".", "?", "!"]
        let keyHeight = (height - gap * 0.5 * 3) / 4
        return VStack(spacing: gap * 0.5) {
            ForEach(marks, id: \.self) { mark in
                InkKey(
                    palette: palette,
                    title: mark,
                    titleFont: fonts.swiftUIFont(size: 21, weight: .regular),
                    isFunction: true
                ) {
                    model.insertSymbol(mark)
                }
                .frame(width: width, height: keyHeight)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: T9 grid

    private func t9Grid(unit: CGFloat, rowHeight: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { column in
                        let key = T9Keypad.all[row * 3 + column]
                        InkKey(
                            palette: palette,
                            title: key.letters,
                            subtitle: key.digit,
                            titleFont: fonts.swiftUIFont(size: 18, weight: .medium)
                        ) {
                            if key.digit == "1" {
                                model.showPage(.symbols)
                            } else {
                                model.tapDigit(key.digit)
                            }
                        }
                        .frame(width: unit, height: rowHeight)
                    }
                }
            }
        }
        .frame(width: unit * 3 + gap * 2)
    }

    // MARK: Right function column

    private func functionColumn(width: CGFloat, rowHeight: CGFloat, bottomHeight: CGFloat) -> some View {
        let tallHeight = rowHeight + gap + bottomHeight
        return VStack(spacing: gap) {
            InkRepeatKey(
                palette: palette,
                titleFont: fonts.swiftUIFont(size: 18, weight: .regular),
                systemImage: "delete.left"
            ) {
                model.backspace()
            }
            .frame(width: width, height: rowHeight)

            InkKey(
                palette: palette,
                title: "重输",
                titleFont: fonts.swiftUIFont(size: 15, weight: .regular),
                isFunction: true
            ) {
                model.resetBuffer()
            }
            .frame(width: width, height: rowHeight)

            InkKey(
                palette: palette,
                title: model.returnKeyLabel,
                titleFont: fonts.swiftUIFont(size: 15, weight: .regular),
                isFunction: true
            ) {
                model.newline()
            }
            .frame(width: width, height: tallHeight)
        }
        .frame(width: width)
    }

    // MARK: Bottom bar

    private func bottomBar(unit: CGFloat, punctWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) {
            InkKey(
                palette: palette,
                title: model.page == .t9 ? "符号" : "ABC",
                titleFont: fonts.swiftUIFont(size: 15, weight: .regular),
                isFunction: true
            ) {
                model.showPage(model.page == .t9 ? .symbols : .t9)
            }
            .frame(width: punctWidth, height: height)

            InkKey(
                palette: palette,
                title: "123",
                titleFont: fonts.swiftUIFont(size: 15, weight: .regular),
                isFunction: true
            ) {
                model.showPage(model.page == .numbers ? .t9 : .numbers)
            }
            .frame(width: unit * 0.62, height: height)

            InkKey(
                palette: palette,
                title: "空格",
                titleFont: fonts.swiftUIFont(size: 14, weight: .regular)
            ) {
                model.space()
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)

            ModeKey(palette: palette, mode: model.mode, fonts: fonts) {
                model.toggleMode()
            }
            .frame(width: unit * 0.62, height: height)

            if model.showsGlobe {
                InkKey(
                    palette: palette,
                    systemImage: "globe",
                    titleFont: fonts.swiftUIFont(size: 16, weight: .regular),
                    isFunction: true
                ) {
                    model.nextKeyboard()
                }
                .frame(width: unit * 0.52, height: height)
            }
        }
    }

    // MARK: Symbol pad

    private func symbolPad() -> some View {
        InkSymbolPad(
            symbols: InkSymbols.wide,
            columns: 5,
            palette: palette,
            fonts: fonts,
            onTap: { model.insertSymbol($0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Number pad

    private func numberPad() -> some View {
        InkSymbolPad(
            symbols: InkSymbols.numbers,
            columns: 4,
            palette: palette,
            fonts: fonts,
            onTap: { model.insertSymbol($0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Symbol / number grid

struct InkSymbolPad: View {
    let symbols: [String]
    let columns: Int
    let palette: InkPalette
    let fonts: InkFontCenter
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let rows = max(1, (symbols.count + columns - 1) / columns)
            let cellHeight = max(28, (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            let grid = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
            LazyVGrid(columns: grid, spacing: spacing) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { item in
                    InkKey(
                        palette: palette,
                        title: item.element,
                        titleFont: fonts.swiftUIFont(size: 17, weight: .regular)
                    ) {
                        onTap(item.element)
                    }
                    .frame(height: cellHeight)
                }
            }
        }
    }
}

// MARK: - Key components

struct InkKey: View {
    let palette: InkPalette
    var title: String? = nil
    var subtitle: String? = nil
    var systemImage: String? = nil
    var titleFont: Font = .system(size: 16)
    var isFunction: Bool = false
    var tint: Color? = nil
    var corner: CGFloat = 8
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                label
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(palette.secondaryText.opacity(0.9))
                        .padding(.top, 4)
                        .padding(.trailing, 5)
                }
            }
        }
        .buttonStyle(InkKeyButtonStyle(palette: palette, isFunction: isFunction, corner: corner))
    }

    @ViewBuilder private var label: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(titleFont)
                .foregroundStyle(tint ?? palette.keyText)
        } else if let title {
            Text(title)
                .font(titleFont)
                .foregroundStyle(tint ?? palette.keyText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 2)
        }
    }
}

struct InkKeyButtonStyle: ButtonStyle {
    let palette: InkPalette
    var isFunction: Bool = false
    var corner: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(configuration.isPressed
                          ? palette.keyFillPressed
                          : (isFunction ? palette.paperDeep : palette.keyFill))
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.28 : 0.09),
                        radius: configuration.isPressed ? 0 : 0.8,
                        x: 0,
                        y: configuration.isPressed ? 0 : 0.8
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(palette.keyStroke.opacity(0.75), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

/// Backspace with hold-to-repeat (deletes every ~70 ms while held).
struct InkRepeatKey: View {
    let palette: InkPalette
    var titleFont: Font = .system(size: 18)
    var systemImage: String? = nil
    let action: () -> Void

    @State private var timer: Timer?
    @State private var pressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(pressed ? palette.keyFillPressed : palette.paperDeep)
                .shadow(
                    color: Color.black.opacity(palette.isDark ? 0.28 : 0.09),
                    radius: pressed ? 0 : 0.8,
                    x: 0,
                    y: pressed ? 0 : 0.8
                )
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.keyStroke.opacity(0.75), lineWidth: 0.6)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(titleFont)
                    .foregroundStyle(palette.keyText)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    let fire = action
                    fire()
                    let newTimer = Timer(timeInterval: 0.07, repeats: true) { _ in
                        fire()
                    }
                    RunLoop.main.add(newTimer, forMode: .common)
                    timer = newTimer
                }
                .onEnded { _ in
                    pressed = false
                    timer?.invalidate()
                    timer = nil
                }
        )
    }
}

struct ModeKey: View {
    let palette: InkPalette
    let mode: InkMode
    let fonts: InkFontCenter
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("中")
                    .font(fonts.swiftUIFont(size: 13, weight: mode == .chinese ? .semibold : .regular))
                    .foregroundStyle(mode == .chinese ? palette.seal : palette.secondaryText)
                Text("英")
                    .font(fonts.swiftUIFont(size: 13, weight: mode == .english ? .semibold : .regular))
                    .foregroundStyle(mode == .english ? palette.seal : palette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(InkKeyButtonStyle(palette: palette, isFunction: true))
    }
}

// MARK: - Key data

struct T9KeyModel: Identifiable {
    let id: Int
    let digit: String
    let letters: String
}

enum T9Keypad {
    static let all: [T9KeyModel] = [
        T9KeyModel(id: 0, digit: "1", letters: "@#"),
        T9KeyModel(id: 1, digit: "2", letters: "ABC"),
        T9KeyModel(id: 2, digit: "3", letters: "DEF"),
        T9KeyModel(id: 3, digit: "4", letters: "GHI"),
        T9KeyModel(id: 4, digit: "5", letters: "JKL"),
        T9KeyModel(id: 5, digit: "6", letters: "MNO"),
        T9KeyModel(id: 6, digit: "7", letters: "PQRS"),
        T9KeyModel(id: 7, digit: "8", letters: "TUV"),
        T9KeyModel(id: 8, digit: "9", letters: "WXYZ")
    ]
}

enum InkSymbols {
    static let wide: [String] = [
        "，", "。", "？", "！", "：",
        "；", "、", "…", "—", "～",
        "（", "）", "【", "】", "《",
        "》", "“", "”", "‘", "’",
        "￥", "$", "#", "@", "%"
    ]

    static let numbers: [String] = [
        "1", "2", "3", "4",
        "5", "6", "7", "8",
        "9", "0", ".", "-",
        "/", ":", ";", "("
    ]

    /// Half-width punctuation for the English 26-key symbol page.
    static let ascii: [String] = [
        ",", ".", "?", "!", ":",
        ";", "'", "\"", "(", ")",
        "[", "]", "{", "}", "<",
        ">", "/", "-", "_", "=",
        "+", "@", "#", "$", "%",
        "&", "*", "~", "…", "·"
    ]
}
