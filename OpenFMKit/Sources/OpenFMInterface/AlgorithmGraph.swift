// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// The live routing diagram. Carriers sit on the bottom row and feed the
/// output; modulators stack above whatever they shape.
///
/// Each operator is a control: drag up and down for output level, sideways
/// for frequency ratio, tap to select, double-tap to switch it on or off.
/// While you drag, the operator and everything downstream of it light up.
struct AlgorithmGraph: View {
    @Environment(SynthModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let algorithm = model.algorithm
            let layout = GraphLayout(algorithm: algorithm, size: geo.size)
            let affected = model.affectedOps
            let feedback = model.value(.feedback)
            let feedbackActive = model.focus == .feedback

            ZStack {
                // Modulation paths.
                EdgeShape(points: layout.vector, node: layout.node, edges: algorithm.edges)
                    .stroke(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                EdgeShape(points: layout.vector, node: layout.node,
                          edges: algorithm.edges.filter { affected.contains($0.from) && affected.contains($0.to) })
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Carriers drop into the output bus.
                OutputShape(points: layout.vector, node: layout.node, carriers: algorithm.carriers, busY: layout.busY)
                    .stroke(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                OutputShape(points: layout.vector, node: layout.node,
                            carriers: algorithm.carriers.filter(affected.contains), busY: layout.busY, stemsOnly: true)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                FeedbackShape(points: layout.vector, node: layout.node, loop: algorithm.feedback)
                    .stroke(feedbackActive ? Theme.accent : (feedback > 0 ? Theme.secondary : Theme.tertiary),
                            style: StrokeStyle(lineWidth: feedbackActive ? 2 : 1.5, lineCap: .round, lineJoin: .round,
                                               dash: feedback > 0 ? [] : [2, 4]))

                Text("OUT")
                    .labelStyle(9)
                    .position(x: layout.busLabelX, y: layout.busY)

                ForEach(1...6, id: \.self) { op in
                    OperatorNode(op: op, size: layout.node)
                        .position(layout.point(op))
                        .zIndex(model.focus?.op == op ? 1 : 0)
                }
            }
            .animation(.snappy(duration: 0.32), value: algorithm.number)
        }
    }
}

/// Converts grid positions to points for a given canvas size.
struct GraphLayout {
    let node: CGFloat
    let busY: CGFloat
    let busLabelX: CGFloat
    private let points: [CGPoint]

    init(algorithm: Algorithm, size: CGSize) {
        let busSpace: CGFloat = 30
        let sideSpace: CGFloat = 44
        let pitchX = min(124, (size.width - sideSpace * 2) / algorithm.columns)
        let pitchY = min(116, (size.height - busSpace - 8) / CGFloat(algorithm.rows))
        node = max(28, min(76, pitchX - 20, pitchY - 24))
        let width = pitchX * algorithm.columns
        let height = pitchY * CGFloat(algorithm.rows)
        let originX = (size.width - width) / 2 + pitchX / 2
        let top = (size.height - busSpace - height) / 2
        let placed = algorithm.positions.map { p in
            CGPoint(x: originX + p.x * pitchX,
                    y: top + (CGFloat(algorithm.rows) - 1 - p.y) * pitchY + pitchY / 2)
        }
        let carrierY = top + height - pitchY / 2
        busY = carrierY + node / 2 + 16
        let maxX = algorithm.carriers.map { placed[$0 - 1].x }.max() ?? 0
        busLabelX = maxX + node / 2 + 24
        points = placed
    }

    func point(_ op: Int) -> CGPoint { points[op - 1] }
    var vector: GraphVector { GraphVector(points) }
}

/// Six points as one animatable value, so paths follow the operators when the
/// algorithm changes.
struct GraphVector: VectorArithmetic {
    var v: [Double]

    init(_ points: [CGPoint]) { v = points.flatMap { [$0.x, $0.y] } }
    private init(raw: [Double]) { v = raw }

    func point(_ op: Int) -> CGPoint { CGPoint(x: v[(op - 1) * 2], y: v[(op - 1) * 2 + 1]) }

    static var zero: GraphVector { GraphVector(raw: Array(repeating: 0, count: 12)) }
    static func + (a: GraphVector, b: GraphVector) -> GraphVector { GraphVector(raw: zip(a.v, b.v).map(+)) }
    static func - (a: GraphVector, b: GraphVector) -> GraphVector { GraphVector(raw: zip(a.v, b.v).map(-)) }
    mutating func scale(by rhs: Double) { v = v.map { $0 * rhs } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }
}

private struct EdgeShape: Shape {
    var points: GraphVector
    let node: CGFloat
    let edges: [Algorithm.Edge]

    var animatableData: GraphVector {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            let from = points.point(edge.from), to = points.point(edge.to)
            let a = CGPoint(x: from.x, y: from.y + node / 2)
            let b = CGPoint(x: to.x, y: to.y - node / 2)
            path.move(to: a)
            if abs(a.x - b.x) < 0.5 {
                path.addLine(to: b)
            } else {
                let mid = (a.y + b.y) / 2
                path.addCurve(to: b, control1: CGPoint(x: a.x, y: mid), control2: CGPoint(x: b.x, y: mid))
            }
        }
        return path
    }
}

private struct OutputShape: Shape {
    var points: GraphVector
    let node: CGFloat
    let carriers: [Int]
    let busY: CGFloat
    var stemsOnly = false

    var animatableData: GraphVector {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let xs = carriers.map { points.point($0).x }
        for op in carriers {
            let p = points.point(op)
            path.move(to: CGPoint(x: p.x, y: p.y + node / 2))
            path.addLine(to: CGPoint(x: p.x, y: busY))
        }
        if !stemsOnly, let minX = xs.min(), let maxX = xs.max() {
            path.move(to: CGPoint(x: minX, y: busY))
            path.addLine(to: CGPoint(x: maxX + node / 2 + 8, y: busY))
        }
        return path
    }
}

private struct FeedbackShape: Shape {
    var points: GraphVector
    let node: CGFloat
    let loop: Algorithm.Edge

    var animatableData: GraphVector {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let from = points.point(loop.from), to = points.point(loop.to)
        let isSelf = loop.from == loop.to
        let spread = isSelf ? node * 0.22 : 0
        let x = max(from.x, to.x) + node / 2
        let reach: CGFloat = 12
        let a = CGPoint(x: from.x + node / 2, y: from.y + spread)
        let b = CGPoint(x: to.x + node / 2, y: to.y - spread)
        var path = Path()
        path.move(to: a)
        path.addArc(tangent1End: CGPoint(x: x + reach, y: a.y), tangent2End: CGPoint(x: x + reach, y: b.y), radius: 5)
        path.addArc(tangent1End: CGPoint(x: x + reach, y: b.y), tangent2End: b, radius: 5)
        path.addLine(to: b)
        return path
    }
}

// MARK: - Operator

/// One operator in the diagram.
struct OperatorNode: View {
    @Environment(SynthModel.self) private var model
    let op: Int
    let size: CGFloat

    private enum Axis { case level, ratio }
    @State private var start: (level: Double, coarse: Double)?
    @State private var axis: Axis?
    @GestureState private var isDragging = false

    var body: some View {
        let level = model.value(.op(op, .level))
        let on = model.isOn(op)
        let focused = model.focus?.op == op
        let affected = model.affectedOps.contains(op)
        let selected = model.selectedOp == op
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        let tint = focused || affected ? Theme.accent : Theme.text

        ZStack {
            shape.fill(Theme.surface)
            // The fill height is the output level.
            Rectangle()
                .fill(tint.opacity(focused ? 0.34 : (affected ? 0.22 : 0.12)))
                .frame(height: size * level / 99)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(shape)
            VStack(spacing: 0) {
                Text("\(op)")
                    .font(.value(size * 0.38, weight: .semibold))
                    .foregroundStyle(focused ? Theme.accent : Theme.text)
                if size >= 44 {
                    Text(model.frequencyText(op))
                        .font(.value(max(8, size * 0.15)))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 3)
            shape.strokeBorder(focused || affected ? Theme.accent : (selected ? Theme.text : Theme.tertiary),
                               style: StrokeStyle(lineWidth: focused || selected ? 2 : 1.5, dash: on ? [] : [3, 3]))
        }
        .frame(width: size, height: size)
        .opacity(on ? 1 : 0.4)
        .overlay(alignment: .top) {
            if start != nil, axis != nil { bubble.offset(y: -30).transition(.opacity) }
        }
        .overlay(alignment: .leading) {
            // The selected operator shows which ways it can be dragged.
            if selected, start == nil, on {
                VStack(spacing: 5) {
                    Image(systemName: "arrow.up.and.down")
                    Image(systemName: "arrow.left.and.right")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .offset(x: -17)
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle().inset(by: -6))
        .gesture(drag)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            model.toggle(op)
            Haptics.tap()
        })
        .onChange(of: isDragging) { _, dragging in
            if !dragging, start != nil {
                start = nil
                axis = nil
                model.endEditing()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Operator \(op), \(model.algorithm.isCarrier(op) ? "carrier" : "modulator")")
        .accessibilityValue(on ? "Level \(Int(level)), \(model.frequencyText(op))" : "Off")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAdjustableAction { direction in
            model.set(.op(op, .level), to: level + (direction == .increment ? 1 : -1))
        }
        .accessibilityAction(named: on ? "Switch off" : "Switch on") { model.toggle(op) }
    }

    private var bubble: some View {
        Text(axis == .ratio ? model.frequencyText(op) : "LEVEL \(Int(model.value(.op(op, .level))))")
            .font(.value(12, weight: .semibold))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.text, in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { g in
                if start == nil {
                    start = (model.value(.op(op, .level)), model.value(.op(op, .coarse)))
                    model.selectedOp = op
                    Haptics.grab()
                }
                guard let start else { return }
                let dx = g.translation.width, dy = g.translation.height
                if axis == nil, max(abs(dx), abs(dy)) > 8 {
                    // Lock to the direction the finger left in.
                    axis = abs(dy) >= abs(dx) ? .level : .ratio
                    model.beginEditing(.op(op, axis == .level ? .level : .coarse))
                }
                switch axis {
                case .level:
                    let p = Param.op(op, .level)
                    let before = model.value(p)
                    model.set(p, to: start.level - dy / 1.8)
                    Haptics.change(p, from: before, to: model.value(p))
                case .ratio:
                    let p = Param.op(op, .coarse)
                    let before = model.value(p)
                    model.set(p, to: start.coarse + dx / 18)
                    Haptics.change(p, from: before, to: model.value(p))
                case nil:
                    break
                }
            }
    }
}

// MARK: - Glyph

/// A small static picture of an algorithm, for pickers and lists.
struct AlgorithmGlyph: View {
    let algorithm: Algorithm
    var color: Color = Theme.text

    var body: some View {
        Canvas { context, size in
            let dot = min(size.width / (algorithm.columns * 1.5), size.height / (CGFloat(algorithm.rows) * 1.5), 9)
            let pitchX = algorithm.columns > 1 ? min((size.width - dot) / (algorithm.columns - 1), dot * 1.7) : 0
            let pitchY = algorithm.rows > 1 ? min((size.height - dot) / CGFloat(algorithm.rows - 1), dot * 1.7) : 0
            let width = pitchX * (algorithm.columns - 1), height = pitchY * CGFloat(algorithm.rows - 1)
            let origin = CGPoint(x: (size.width - width) / 2, y: (size.height + height) / 2)
            func point(_ op: Int) -> CGPoint {
                let p = algorithm.positions[op - 1]
                return CGPoint(x: origin.x + p.x * pitchX, y: origin.y - p.y * pitchY)
            }
            var lines = Path()
            for edge in algorithm.edges {
                lines.move(to: point(edge.from))
                lines.addLine(to: point(edge.to))
            }
            context.stroke(lines, with: .color(color.opacity(0.45)), lineWidth: 1)
            for op in 1...6 {
                let p = point(op)
                let rect = CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)
                let shape = Path(roundedRect: rect, cornerRadius: dot * 0.28)
                if algorithm.isCarrier(op) {
                    context.fill(shape, with: .color(color))
                } else {
                    context.fill(shape, with: .color(Theme.surface))
                    context.stroke(shape, with: .color(color), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
