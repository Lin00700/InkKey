//
//  EnglishKeyboard.swift
//  InkKeyKeyboard
//
//  The 26-key QWERTY layout used for English input:
//    Q W E R T Y U I O P
//    A S D F G H J K L
//    ⇧  Z X C V B N M  ⌫
//    123  符号  空格  中/英  搜索/发送/…  🌐
//

import SwiftUI

struct EnglishKeysArea: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject private var fonts = InkFontCenter.shared
    let palette: InkPalette

    private var gap: CGFloat { KeyboardMetrics.gap }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let unit = max(24, (width - gap * 9) / 10)
            let bottomHeight = max(34, height * 0.24)
            let letterHeight = max(60, height - bottomHeight - gap)

            VStack(spacing: gap) {
                if model.page == .t9 {
                    qwerty(unit: unit, height: letterHeight)
                        .frame(height: letterHeight)
                } else if model.page == .numbers {
                    InkSymbolPad(
                        symbols: InkSymbols.numbers,
                        columns: 4,
                        palette: palette,
                        fonts: fonts,
                        onTap: { model.insertSymbol($0) }
                    )
                    .frame(height: letterHeight)
                } else {
                    InkSymbolPad(
                        symbols: InkSymbols.ascii,
                        columns: 5,
                        palette: palette,
                        fonts: fonts,
                        onTap: { model.insertSymbol($0) }
                    )
                    .frame(height: letterHeight)
                }

                bottomBar(unit: unit, height: bottomHeight)
                    .frame(height: bottomHeight)
            }
        }
    }

    // MARK: Letter rows

    private func qwerty(unit: CGFloat, height: CGFloat) -> some View {
        let rowHeight = max(30, (height - gap * 2) / 3)
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach(Self.row1, id: \.self) { letter in
                    letterKey(letter, width: unit, height: rowHeight)
                }
            }
            .frame(height: rowHeight)

            HStack(spacing: gap) {
                ForEach(Self.row2, id: \.self) { letter in
                    letterKey(letter, width: unit, height: rowHeight)
                }
            }
            .padding(.horizontal, (unit + gap) / 2)
            .frame(height: rowHeight)

            HStack(spacing: gap) {
                ShiftKey(palette: palette, fonts: fonts, state: model.shift) { doubleTap in
                    model.toggleShift(doubleTap: doubleTap)
                }
                .frame(width: unit * 1.5, height: rowHeight)

                ForEach(Self.row3, id: \.self) { letter in
                    letterKey(letter, width: unit, height: rowHeight)
                }

                InkRepeatKey(
                    palette: palette,
                    titleFont: fonts.swiftUIFont(size: 18, weight: .regular),
                    systemImage: "delete.left"
                ) {
                    model.backspace()
                }
                .frame(width: unit * 1.5, height: rowHeight)
            }
            .frame(height: rowHeight)
        }
    }

    private func letterKey(_ letter: String, width: CGFloat, height: CGFloat) -> some View {
        InkKey(
            palette: palette,
            title: letter.uppercased(),
            titleFont: fonts.swiftUIFont(size: 20, weight: .regular)
        ) {
            model.tapLetter(letter)
        }
        .frame(width: width, height: height)
    }

    // MARK: Bottom bar

    private func bottomBar(unit: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) {
            InkKey(
                palette: palette,
                title: model.page == .numbers ? "ABC" : "123",
                titleFont: fonts.swiftUIFont(size: 15, weight: .regular),
                isFunction: true
            ) {
                model.showPage(model.page == .numbers ? .t9 : .numbers)
            }
            .frame(width: unit * 0.86, height: height)

            InkKey(
                palette: palette,
                title: model.page == .symbols ? "ABC" : "符号",
                titleFont: fonts.swiftUIFont(size: 14, weight: .regular),
                isFunction: true
            ) {
                model.showPage(model.page == .symbols ? .t9 : .symbols)
            }
            .frame(width: unit * 0.86, height: height)

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
            .frame(width: unit * 0.86, height: height)

            InkAccentKey(
                palette: palette,
                title: model.returnKeyLabel,
                titleFont: fonts.swiftUIFont(size: 14, weight: .medium)
            ) {
                model.newline()
            }
            .frame(width: unit * 1.34, height: height)

            if model.showsGlobe {
                InkKey(
                    palette: palette,
                    systemImage: "globe",
                    titleFont: fonts.swiftUIFont(size: 16, weight: .regular),
                    isFunction: true
                ) {
                    model.nextKeyboard()
                }
                .frame(width: unit * 0.62, height: height)
            }
        }
    }

    // MARK: Rows

    private static let row1: [String] = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private static let row2: [String] = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private static let row3: [String] = ["z", "x", "c", "v", "b", "n", "m"]
}

// MARK: - Shift

/// Tap for one capital letter, double-tap for caps lock.
struct ShiftKey: View {
    let palette: InkPalette
    let fonts: InkFontCenter
    let state: InkShiftState
    let onTap: (Bool) -> Void

    @State private var lastTap: Date = .distantPast

    private var icon: String {
        switch state {
        case .off: return "shift"
        case .single: return "shift.fill"
        case .caps: return "capslock.fill"
        }
    }

    private var active: Bool { state != .off }

    var body: some View {
        Button {
            let now = Date()
            let isDouble = now.timeIntervalSince(lastTap) < 0.45
            lastTap = now
            onTap(isDouble)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(fonts.swiftUIFont(size: 17, weight: .regular))
                    .foregroundStyle(active ? palette.seal : palette.keyText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if state == .caps {
                    Text("锁")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.seal)
                        .padding(.top, 3)
                        .padding(.trailing, 4)
                }
            }
        }
        .buttonStyle(InkKeyButtonStyle(palette: palette, isFunction: true))
    }
}

// MARK: - Accent key (return)

struct InkAccentKey: View {
    let palette: InkPalette
    let title: String
    var titleFont: Font = .system(size: 14)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.seal.opacity(0.92))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
