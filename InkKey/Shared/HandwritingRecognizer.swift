//
//  HandwritingRecognizer.swift
//  InkKey / InkKeyKeyboard
//
//  Offline Chinese handwriting recognition.
//
//  Templates come from the bundled `handwriting.bin` (built by
//  Tools/build_handwriting.py from Make Me a Hanzi's stroke medians): every
//  character stores its strokes resampled to a fixed number of points inside a
//  0-255 box.  Recognition is a small sequence alignment (DTW with skips)
//  between the drawn strokes and each template whose stroke count is within
//  ±2.  The file is read memory-mapped and never turned into objects, so the
//  whole feature costs under a megabyte of RAM and a few milliseconds.
//

import Foundation

/// One point of a drawn or template stroke, in the shared 0-255 box.
struct InkHandwritingPoint {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

final class HandwritingRecognizer {
    static let shared = HandwritingRecognizer()

    /// Lets the desktop checker in Tools/ point at the dataset directly.
    static var resourceURLOverride: URL?

    private static let fileName = "handwriting"
    private static let magic: [UInt8] = [0x49, 0x4B, 0x48, 0x58] // "IKHX"
    private static let maxStrokes = 36

    private var blob: Data?
    private var charCount = 0
    private var pointsPerStroke = 6
    private var recordBase = 12
    private var pointBase = 12
    private(set) var isLoaded = false
    private(set) var loadError: String?
    private(set) var templateCount = 0

    private init() {}

    // MARK: Loading

    func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let url = Self.resourceURLOverride
                ?? Bundle.main.url(forResource: Self.fileName, withExtension: "bin") else {
            loadError = "找不到手写模板"
            return
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let ok = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
                guard raw.count >= 12 else { return false }
                for i in 0..<4 where raw[i] != Self.magic[i] { return false }
                let version = Int(raw[4]) | (Int(raw[5]) << 8)
                guard version == 1 else { return false }
                let pps = Int(raw[6])
                let count = Int(raw[8]) | (Int(raw[9]) << 8) | (Int(raw[10]) << 16) | (Int(raw[11]) << 24)
                guard pps >= 2, pps <= 32, count > 0 else { return false }
                let base = 12 + count * 16
                guard base <= raw.count else { return false }
                self.pointsPerStroke = pps
                self.charCount = count
                self.templateCount = count
                self.recordBase = 12
                self.pointBase = base
                return true
            }
            guard ok else {
                loadError = "手写模板格式不匹配"
                charCount = 0
                return
            }
            blob = data
        } catch {
            loadError = "手写模板读取失败：\(error.localizedDescription)"
            charCount = 0
        }
    }

    // MARK: Recognition

    /// Ranks the characters that could be what the user just drew.
    /// `strokes` are canvas points in the same top-left origin space as the
    /// templates; they are normalised here so callers can pass raw touches.
    func recognize(strokes: [[InkHandwritingPoint]], limit: Int = 12) -> [UInt32] {
        loadIfNeeded()
        guard let blob, charCount > 0, !strokes.isEmpty else { return [] }
        let prepared = Self.prepare(strokes: strokes, pointsPerStroke: pointsPerStroke)
        guard !prepared.isEmpty else { return [] }

        let userCount = prepared.count
        var top: [(score: Double, codepoint: UInt32)] = []
        top.reserveCapacity(limit)
        var prev = [Double](repeating: 0, count: Self.maxStrokes + 1)
        var cur = [Double](repeating: 0, count: Self.maxStrokes + 1)

        blob.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for index in 0..<charCount {
                let base = recordBase + index * 16
                let strokeCount = Int(raw[base + 4])
                guard strokeCount > 0, strokeCount == userCount || abs(strokeCount - userCount) <= 2 else { continue }
                guard strokeCount <= Self.maxStrokes, strokeCount <= userCount + 2 else { continue }
                let codepoint = UInt32(raw[base])
                    | (UInt32(raw[base + 1]) << 8)
                    | (UInt32(raw[base + 2]) << 16)
                    | (UInt32(raw[base + 3]) << 24)
                let offset = Int(UInt32(raw[base + 8])
                    | (UInt32(raw[base + 9]) << 8)
                    | (UInt32(raw[base + 10]) << 16)
                    | (UInt32(raw[base + 11]) << 24))
                let start = pointBase + offset * 2
                guard start + strokeCount * pointsPerStroke * 2 <= raw.count else { continue }

                let score = Self.cost(
                    user: prepared,
                    raw: raw,
                    templateStart: start,
                    strokeCount: strokeCount,
                    pointsPerStroke: pointsPerStroke,
                    prev: &prev,
                    cur: &cur
                )
                Self.insert(score: score, codepoint: codepoint, into: &top, limit: limit)
            }
        }
        return top.map { $0.codepoint }
    }

    private static func insert(score: Double,
                               codepoint: UInt32,
                               into top: inout [(score: Double, codepoint: UInt32)],
                               limit: Int) {
        if top.count < limit {
            top.append((score, codepoint))
            top.sort { $0.score < $1.score }
            return
        }
        guard let worst = top.last, score < worst.score else { return }
        top[top.count - 1] = (score, codepoint)
        top.sort { $0.score < $1.score }
    }

    // MARK: Matching

    /// Sequence alignment between the drawn strokes and one template.
    /// `skip` prices a stroke that exists on only one side, so a missing or
    /// extra stroke costs a little instead of ruining the character.
    private static func cost(user: [[InkHandwritingPoint]],
                             raw: UnsafeRawBufferPointer,
                             templateStart: Int,
                             strokeCount: Int,
                             pointsPerStroke pps: Int,
                             prev: inout [Double],
                             cur: inout [Double]) -> Double {
        let n = user.count
        let m = strokeCount
        guard n > 0, m > 0, prev.count > m, cur.count > m else { return .greatestFiniteMagnitude }
        let skip = 0.42

        for j in 0...m { prev[j] = Double(j) * skip }
        for i in 1...n {
            cur[0] = Double(i) * skip
            let stroke = user[i - 1]
            for j in 1...m {
                let start = templateStart + (j - 1) * pps * 2
                var forward = 0.0
                var backward = 0.0
                var k = 0
                while k < pps {
                    let ux = stroke[k].x
                    let uy = stroke[k].y
                    let fx = Double(raw[start + k * 2])
                    let fy = Double(raw[start + k * 2 + 1])
                    let rx = Double(raw[start + (pps - 1 - k) * 2])
                    let ry = Double(raw[start + (pps - 1 - k) * 2 + 1])
                    let dxf = ux - fx, dyf = uy - fy
                    let dxr = ux - rx, dyr = uy - ry
                    forward += (dxf * dxf + dyf * dyf).squareRoot()
                    backward += (dxr * dxr + dyr * dyr).squareRoot()
                    k += 1
                }
                let unit = Double(pps)
                let distance = min(forward, backward) / unit / 60.0
                let paired = prev[j - 1] + distance
                let skipped = min(prev[j] + skip, cur[j - 1] + skip)
                cur[j] = paired < skipped ? paired : skipped
            }
            swap(&prev, &cur)
        }
        let best = prev[m]
        let span = Double(max(n, m))
        return best / span + 0.9 * Double(abs(n - m)) / span
    }

    // MARK: Geometry

    /// Fits the drawn ink into the 0-255 box (aspect kept) and resamples every
    /// stroke to `pointsPerStroke` points.
    static func prepare(strokes: [[InkHandwritingPoint]], pointsPerStroke pps: Int) -> [[InkHandwritingPoint]] {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var kept: [[InkHandwritingPoint]] = []
        for stroke in strokes where !stroke.isEmpty {
            kept.append(stroke)
            for point in stroke {
                if point.x < minX { minX = point.x }
                if point.y < minY { minY = point.y }
                if point.x > maxX { maxX = point.x }
                if point.y > maxY { maxY = point.y }
            }
        }
        guard !kept.isEmpty, maxX >= minX, maxY >= minY else { return [] }
        if kept.count > maxStrokes { kept = Array(kept.suffix(maxStrokes)) }

        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let scale = 247.0 / max(width, height)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        var out: [[InkHandwritingPoint]] = []
        out.reserveCapacity(kept.count)
        for stroke in kept {
            let placed = stroke.map { point in
                InkHandwritingPoint(
                    x: min(255, max(0, (point.x - centerX) * scale + 127.5)),
                    y: min(255, max(0, (point.y - centerY) * scale + 127.5))
                )
            }
            out.append(resample(placed, count: pps))
        }
        return out
    }

    /// Uniform arc-length resampling: `count` points from the first to the last.
    static func resample(_ points: [InkHandwritingPoint], count: Int) -> [InkHandwritingPoint] {
        guard count > 1 else { return points.first.map { [$0] } ?? [] }
        if points.count == 1 { return [InkHandwritingPoint](repeating: points[0], count: count) }
        if points.count == count { return points }

        var lengths = [Double](repeating: 0, count: points.count)
        var total = 0.0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            total += (dx * dx + dy * dy).squareRoot()
            lengths[i] = total
        }
        guard total > 0.0001 else {
            return [InkHandwritingPoint](repeating: points[0], count: count)
        }

        var out: [InkHandwritingPoint] = []
        out.reserveCapacity(count)
        let step = total / Double(count - 1)
        var segment = 1
        for k in 0..<count {
            let target = step * Double(k)
            while segment < lengths.count && lengths[segment] < target { segment += 1 }
            if segment >= lengths.count {
                out.append(points[points.count - 1])
                continue
            }
            let from = lengths[segment - 1]
            let to = lengths[segment]
            let t = to - from <= 0.000001 ? 0 : (target - from) / (to - from)
            let x = points[segment - 1].x + (points[segment].x - points[segment - 1].x) * t
            let y = points[segment - 1].y + (points[segment].y - points[segment - 1].y) * t
            out.append(InkHandwritingPoint(x: x, y: y))
        }
        return out
    }
}
