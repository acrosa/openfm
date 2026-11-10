// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

/// The routing of one of the 32 six-operator algorithms, as a graph the
/// interface can draw.
///
/// Operators are numbered 1...6 as on the front panel. The graph is derived
/// from the same routing flags the engine uses (see `Algorithm.flagTable`),
/// so the diagram can never disagree with what is heard.
public struct Algorithm: Sendable {
    public struct Edge: Hashable, Sendable {
        public let from: Int   // modulator
        public let to: Int     // operator being modulated
    }

    /// 1...32
    public let number: Int
    public let edges: [Edge]
    public let carriers: [Int]
    /// Feedback loop: the output of `from` modulates `to`. Equal for a
    /// self-modulating operator.
    public let feedback: Edge
    /// Grid position per operator (index = number - 1). x in columns, y in
    /// rows above the output; carriers sit on row 0.
    public let positions: [CGPoint]
    public let columns: Double
    public let rows: Int

    public func isCarrier(_ op: Int) -> Bool { carriers.contains(op) }
    public func targets(of op: Int) -> [Int] { edges.filter { $0.from == op }.map(\.to) }
    public func modulators(of op: Int) -> [Int] { edges.filter { $0.to == op }.map(\.from) }

    /// Every operator whose sound changes when `op` changes: `op` itself and
    /// everything it modulates, directly or through a chain.
    public func downstream(of op: Int) -> Set<Int> {
        var seen: Set<Int> = [op]
        var stack = [op]
        while let o = stack.popLast() {
            for t in targets(of: o) where !seen.contains(t) {
                seen.insert(t)
                stack.append(t)
            }
        }
        return seen
    }

    /// Operators inside the feedback loop.
    public var feedbackOps: Set<Int> {
        var ops: Set<Int> = [feedback.from, feedback.to]
        // A multi-operator loop runs from `to` down the chain to `from`.
        var o = feedback.to
        while o != feedback.from, let next = targets(of: o).first {
            ops.insert(next)
            o = next
        }
        return ops
    }

    public static let all: [Algorithm] = (0..<32).map(derive)

    public static func number(_ n: Int) -> Algorithm { all[min(max(n, 1), 32) - 1] }
}

// MARK: - Routing table

extension Algorithm {
    private static let outBusOne = 1, outBusTwo = 2, outBusAdd = 4
    private static let fbIn = 0x40, fbOut = 0x80

    /// Routing flags per algorithm, operator slots ordered OP6...OP1.
    /// Identical to the table in MSFA's fm_core.cc (Apache 2.0, Google Inc.);
    /// a unit test checks it against the engine.
    public static let flagTable: [[Int]] = [
        [0xc1, 0x11, 0x11, 0x14, 0x01, 0x14], [0x01, 0x11, 0x11, 0x14, 0xc1, 0x14],
        [0xc1, 0x11, 0x14, 0x01, 0x11, 0x14], [0x41, 0x11, 0x94, 0x01, 0x11, 0x14],
        [0xc1, 0x14, 0x01, 0x14, 0x01, 0x14], [0x41, 0x94, 0x01, 0x14, 0x01, 0x14],
        [0xc1, 0x11, 0x05, 0x14, 0x01, 0x14], [0x01, 0x11, 0xc5, 0x14, 0x01, 0x14],
        [0x01, 0x11, 0x05, 0x14, 0xc1, 0x14], [0x01, 0x05, 0x14, 0xc1, 0x11, 0x14],
        [0xc1, 0x05, 0x14, 0x01, 0x11, 0x14], [0x01, 0x05, 0x05, 0x14, 0xc1, 0x14],
        [0xc1, 0x05, 0x05, 0x14, 0x01, 0x14], [0xc1, 0x05, 0x11, 0x14, 0x01, 0x14],
        [0x01, 0x05, 0x11, 0x14, 0xc1, 0x14], [0xc1, 0x11, 0x02, 0x25, 0x05, 0x14],
        [0x01, 0x11, 0x02, 0x25, 0xc5, 0x14], [0x01, 0x11, 0x11, 0xc5, 0x05, 0x14],
        [0xc1, 0x14, 0x14, 0x01, 0x11, 0x14], [0x01, 0x05, 0x14, 0xc1, 0x14, 0x14],
        [0x01, 0x14, 0x14, 0xc1, 0x14, 0x14], [0xc1, 0x14, 0x14, 0x14, 0x01, 0x14],
        [0xc1, 0x14, 0x14, 0x01, 0x14, 0x04], [0xc1, 0x14, 0x14, 0x14, 0x04, 0x04],
        [0xc1, 0x14, 0x14, 0x04, 0x04, 0x04], [0xc1, 0x05, 0x14, 0x01, 0x14, 0x04],
        [0x01, 0x05, 0x14, 0xc1, 0x14, 0x04], [0x04, 0xc1, 0x11, 0x14, 0x01, 0x14],
        [0xc1, 0x14, 0x01, 0x14, 0x04, 0x04], [0x04, 0xc1, 0x11, 0x14, 0x04, 0x04],
        [0xc1, 0x14, 0x04, 0x04, 0x04, 0x04], [0xc4, 0x04, 0x04, 0x04, 0x04, 0x04],
    ]

    private static func derive(_ index: Int) -> Algorithm {
        let flags = flagTable[index]
        var bus: [Int: [Int]] = [1: [], 2: []]
        var edges: [Edge] = []
        var carriers: [Int] = []
        var fbFrom = 6, fbTo = 6
        for slot in 0..<6 {
            let op = 6 - slot
            let f = flags[slot]
            let inBus = (f >> 4) & 3
            let outBus = f & 3
            if inBus != 0 {
                for m in bus[inBus] ?? [] { edges.append(Edge(from: m, to: op)) }
            }
            if f & fbIn != 0 { fbTo = op }
            if f & fbOut != 0 { fbFrom = op }
            if outBus == 0 {
                carriers.append(op)
            } else if f & outBusAdd != 0 {
                bus[outBus, default: []].append(op)
            } else {
                bus[outBus] = [op]
            }
        }
        carriers.sort()
        let layout = Layout(edges: edges, carriers: carriers)
        return Algorithm(number: index + 1, edges: edges, carriers: carriers,
                         feedback: Edge(from: fbFrom, to: fbTo),
                         positions: layout.positions, columns: layout.columns, rows: layout.rows)
    }
}

// MARK: - Layout

extension Algorithm {
    /// Places carriers on the bottom row and stacks each modulator above what
    /// it modulates. A modulator feeding several operators is centred above
    /// them.
    private struct Layout {
        var positions = [CGPoint](repeating: .zero, count: 6)
        var columns: Double = 1
        var rows = 1

        init(edges: [Edge], carriers: [Int]) {
            func targets(_ op: Int) -> [Int] { edges.filter { $0.from == op }.map(\.to) }
            let shared = Set((1...6).filter { targets($0).count > 1 })
            func children(_ op: Int) -> [Int] {
                edges.filter { $0.to == op && !shared.contains($0.from) }.map(\.from).sorted()
            }

            var x = [Int: Double]()
            var row = [Int: Int]()
            var nextColumn = 0.0
            func place(_ op: Int, _ r: Int) {
                row[op] = r
                let kids = children(op)
                if kids.isEmpty {
                    x[op] = nextColumn
                    nextColumn += 1
                } else {
                    for k in kids { place(k, r + 1) }
                    x[op] = kids.map { x[$0]! }.reduce(0, +) / Double(kids.count)
                }
            }
            for c in carriers { place(c, 0) }
            for op in shared.sorted() {
                let t = targets(op)
                x[op] = t.map { x[$0] ?? 0 }.reduce(0, +) / Double(t.count)
                row[op] = (t.map { row[$0] ?? 0 }.max() ?? 0) + 1
            }
            for op in 1...6 {
                positions[op - 1] = CGPoint(x: x[op] ?? 0, y: Double(row[op] ?? 0))
            }
            columns = max(1, nextColumn)
            rows = (row.values.max() ?? 0) + 1
        }
    }
}

// MARK: - Waveform preview

extension Algorithm {
    /// One cycle of what this patch sounds like at full envelope level,
    /// computed with the same phase-modulation maths as the engine.
    ///
    /// - Parameter bytes: 156 unpacked DX7 voice bytes.
    public static func previewWave(bytes: [UInt8], samples: Int = 192) -> [Float] {
        guard bytes.count >= 156 else { return [] }
        let flags = flagTable[Int(bytes[134] & 31)]
        let fb = Int(bytes[135] & 7)
        let mask = Int(bytes[155])
        var ratio = [Double](repeating: 1, count: 6)
        var amp = [Double](repeating: 0, count: 6)
        for slot in 0..<6 {
            let o = slot * 21
            let level = Double(min(99, bytes[o + 16]))
            // A full-level operator deviates the phase it modulates by two cycles.
            amp[slot] = (mask >> slot) & 1 == 1 && level > 0 ? 2 * pow(2, (level - 99) / 8) : 0
            let coarse = Double(bytes[o + 18] & 31), fine = Double(min(99, bytes[o + 19]))
            if bytes[o + 17] & 1 == 0 {
                ratio[slot] = (coarse == 0 ? 0.5 : coarse) * (1 + fine / 100)
            } else {
                // Fixed operators are drawn relative to middle C.
                ratio[slot] = pow(10, Double(Int(coarse) & 3) + fine / 100) / 261.63
            }
        }
        let fbScale = fb == 0 ? 0 : pow(2, Double(fb - 9))
        var out = [Float](repeating: 0, count: samples)
        var y0 = 0.0, y1 = 0.0
        // Two passes: the first lets the feedback loop settle.
        for pass in 0..<2 {
            for i in 0..<samples {
                let t = Double(i) / Double(samples)
                var busValue = [0.0, 0.0, 0.0]
                var fbOutput = 0.0
                let fbPhase = (y0 + y1) * fbScale
                for slot in 0..<6 {
                    let f = flags[slot]
                    let inBus = (f >> 4) & 3, outBus = f & 3
                    var phase = t * ratio[slot]
                    if inBus != 0 { phase += busValue[inBus] }
                    if f & 0x40 != 0 { phase += fbPhase }
                    let y = sin(2 * .pi * phase) * amp[slot]
                    if f & 0x80 != 0 { fbOutput = y }
                    if outBus == 0 || f & 4 != 0 { busValue[outBus] += y } else { busValue[outBus] = y }
                }
                y0 = y1
                y1 = fbOutput
                if pass == 1 { out[i] = Float(busValue[0]) }
            }
        }
        let peak = out.map { abs($0) }.max() ?? 0
        if peak > 1e-6 { for i in out.indices { out[i] /= peak } }
        return out
    }
}
