//
//  HandwritingPadView.swift
//  InkKeyKeyboard
//
//  手写中文：an ink-wash writing surface plus the five keys a writer needs —
//  撤一笔 / 重写 / 退格 / 空格 / 换行.  Every finished stroke is handed to
//  KeyboardModel, which asks HandwritingRecognizer for characters and drops
//  them into the same bilingual candidate strip (pinyin + 释义 + 🔊).
//

import SwiftUI

struct HandwritingPad: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject private var fonts = InkFontCenter.shared
    let palette: InkPalette

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    private var gap: CGFloat { KeyboardMetrics.gap }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: gap) {
                canvas
                    .frame(width: max(80, geo.size.width - 68))
                controls(height: geo.size.height)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: model.inkSerial) { _, _ in
            strokes = []
            current = []
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.candidateBackground)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.keyFill.opacity(0.35), palette.paperDeep.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // 米字格 — the faint square grid a Chinese writing exercise book uses.
            Canvas { context, size in
                var grid = Path()
                grid.move(to: CGPoint(x: size.width / 2, y: 6))
                grid.addLine(to: CGPoint(x: size.width / 2, y: size.height - 6))
                grid.move(to: CGPoint(x: 6, y: size.height / 2))
                grid.addLine(to: CGPoint(x: size.width - 6, y: size.height / 2))
                let dash = StrokeStyle(lineWidth: 0.7, dash: [3, 4])
                context.stroke(grid, with: .color(palette.divider.opacity(0.55)), style: dash)
            }
            .allowsHitTesting(false)

            inkCanvas

            if strokes.isEmpty && current.isEmpty {
                Text("在这里手写")
                    .font(fonts.swiftUIFont(size: 12, weight: .regular))
                    .foregroundStyle(palette.secondaryText.opacity(0.5))
                    .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.divider.opacity(0.9), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    current.append(value.location)
                }
                .onEnded { value in
                    var stroke = current
                    if stroke.isEmpty { stroke = [value.location] }
                    current = []
                    strokes.append(stroke)
                    model.recognizeInk(strokes)
                }
        )
    }

    private var inkCanvas: some View {
        Canvas { context, size in
            var all = strokes
            if !current.isEmpty { all.append(current) }
            let width = max(5, min(12, size.height * 0.045))
            for stroke in all where !stroke.isEmpty {
                let path = smoothed(stroke)
                // A soft wet edge under a darker core: 墨落在宣纸上.
                context.stroke(
                    path,
                    with: .color(palette.ink.opacity(0.18)),
                    style: StrokeStyle(lineWidth: width * 2.1, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    path,
                    with: .color(palette.ink.opacity(0.88)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Quadratic smoothing through the mid points of the touch samples.
    private func smoothed(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let radius = max(2.5, first == points.last ? 3.5 : 2.5)
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - radius, y: first.y - radius,
                                       width: radius * 2, height: radius * 2))
            return path
        }
        path.move(to: first)
        var index = 1
        while index < points.count {
            let previous = points[index - 1]
            let point = points[index]
            let middle = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            path.addQuadCurve(to: middle, control: previous)
            index += 1
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    // MARK: Right column

    private func controls(height: CGFloat) -> some View {
        let buttonHeight = max(30, (height - gap * 4) / 5)
        return VStack(spacing: gap) {
            InkKey(
                palette: palette,
                title: "撤一笔",
                titleFont: fonts.swiftUIFont(size: 12, weight: .regular),
                isFunction: true
            ) {
                undoStroke()
            }
            .frame(height: buttonHeight)

            InkKey(
                palette: palette,
                title: "重写",
                titleFont: fonts.swiftUIFont(size: 12, weight: .regular),
                isFunction: true
            ) {
                clearAll()
            }
            .frame(height: buttonHeight)

            InkRepeatKey(
                palette: palette,
                titleFont: fonts.swiftUIFont(size: 17, weight: .regular),
                systemImage: "delete.left"
            ) {
                model.backspace()
            }
            .frame(height: buttonHeight)

            InkKey(
                palette: palette,
                title: "空格",
                titleFont: fonts.swiftUIFont(size: 13, weight: .regular)
            ) {
                model.space()
            }
            .frame(height: buttonHeight)

            InkKey(
                palette: palette,
                title: "换行",
                titleFont: fonts.swiftUIFont(size: 13, weight: .regular),
                isFunction: true
            ) {
                model.newline()
            }
            .frame(height: buttonHeight)
        }
    }

    // MARK: Ink bookkeeping

    private func undoStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        model.recognizeInk(strokes)
        InkFeedback.soft()
    }

    private func clearAll() {
        strokes = []
        current = []
        model.recognizeInk([])
        InkFeedback.soft()
    }
}
