//
//  InkStyle.swift
//  InkKey
//
//  Shared ink-wash styling for the host app: paper background, cards,
//  section headers and the little red seal.
//

import SwiftUI

struct InkBackground: View {
    let palette: InkPalette

    var body: some View {
        ZStack {
            palette.paper
            // A few soft ink washes, kept cheap so lists scroll smoothly.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Circle()
                    .fill(palette.inkSoft.opacity(palette.isDark ? 0.10 : 0.055))
                    .frame(width: w * 0.9, height: w * 0.9)
                    .blur(radius: 60)
                    .offset(x: -w * 0.35, y: -h * 0.05)
                Circle()
                    .fill(palette.seal.opacity(palette.isDark ? 0.07 : 0.045))
                    .frame(width: w * 0.6, height: w * 0.6)
                    .blur(radius: 70)
                    .offset(x: w * 0.45, y: h * 0.55)
            }
        }
        .ignoresSafeArea()
    }
}

struct InkCard<Content: View>: View {
    let palette: InkPalette
    let padding: CGFloat
    let content: Content

    init(palette: InkPalette, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.palette = palette
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.keyFill.opacity(palette.isDark ? 0.55 : 0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.divider.opacity(0.9), lineWidth: 0.8)
            )
    }
}

struct InkSectionLabel: View {
    let text: String
    let palette: InkPalette

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1)
                .fill(palette.seal)
                .frame(width: 3, height: 12)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .tracking(2)
                .foregroundStyle(palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InkSeal: View {
    let palette: InkPalette
    var text: String = "墨"
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(palette.seal)
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .stroke(palette.seal.opacity(0.5), lineWidth: 1)
                .padding(3)
            Text(text)
                .font(.system(size: size * 0.56, weight: .semibold))
                .foregroundStyle(palette.paper)
        }
        .frame(width: size, height: size)
    }
}

struct InkDivider: View {
    let palette: InkPalette

    var body: some View {
        Rectangle()
            .fill(palette.divider.opacity(0.7))
            .frame(height: 0.6)
    }
}

/// A thin, hand-drawn-looking brush stroke used under headings.
struct InkUnderline: View {
    let palette: InkPalette
    var width: CGFloat = 96

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 3))
            path.addQuadCurve(to: CGPoint(x: width, y: 2), control: CGPoint(x: width * 0.45, y: 7))
        }
        .stroke(palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .frame(width: width, height: 8)
    }
}
