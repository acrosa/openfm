// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// The whole instrument on one screen, arranged for the space available.
///
/// Two modes share the header and keyboard: **Play** shows a handful of
/// controls, **Edit** shows everything.
///
/// - wide: header, routing diagram beside the editor, keyboard (iPad landscape)
/// - tall: header, diagram above the editor, keyboard (iPad portrait)
/// - compact: header, one page at a time, keyboard (iPhone portrait)
/// - short: like wide with a slim keyboard (iPhone landscape, plug-in windows)
struct RootView: View {
    enum Page: String, CaseIterable {
        case algorithm = "Routing"
        case operators = "Operator"
        case motion = "Motion"
        case effects = "Effects"
    }

    private enum Mode { case wide, tall, compact, short }

    @Environment(SynthModel.self) private var model
    @Environment(\.looper) private var looper
    @State private var page: Page = RootView.initialPage
    @State private var showBrowser = LaunchOptions.value("browser") != nil
    /// Always opens on the simple side: an instrument should be playable the
    /// moment it appears.
    @State private var currentMode = InterfaceMode(rawValue: LaunchOptions.value("mode")?.capitalized ?? "") ?? .play

    private var interfaceMode: Binding<InterfaceMode> { $currentMode }

    var body: some View {
        GeometryReader { geo in
            let mode = mode(for: geo.size)
            let playing = interfaceMode.wrappedValue == .play
            VStack(spacing: 0) {
                HeaderView(compact: mode == .compact || mode == .short, showBrowser: $showBrowser, mode: interfaceMode)
                Theme.line.frame(height: 1)
                if playing {
                    PlayPage(wide: mode == .wide || mode == .tall, tall: mode == .tall, showBrowser: $showBrowser)
                } else {
                    content(mode, size: geo.size)
                }
                Theme.line.frame(height: 1)
                if let looper, mode != .short {
                    LooperStrip(looper: looper)
                    Theme.line.frame(height: 1)
                }
                KeyboardSection()
                    .frame(height: keyboardHeight(mode, size: geo.size) * (playing && mode != .short ? 1.25 : 1))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .defersSystemGestures(on: .bottom)
        .sheet(isPresented: $showBrowser) {
            PresetBrowser()
        }
        .onAppear(perform: applyLaunchArguments)
        .onChange(of: model.selectedOp) { _, _ in
            // Picking an operator in the diagram brings its editor forward.
            if page != .operators, page != .algorithm { page = .operators }
        }
    }

    private func mode(for size: CGSize) -> Mode {
        if size.height < 520, size.width > size.height { return .short }
        if size.width >= 960 { return .wide }
        if size.width >= 700 { return .tall }
        return .compact
    }

    private func keyboardHeight(_ mode: Mode, size: CGSize) -> CGFloat {
        switch mode {
        case .wide: min(max(size.height * 0.25, 180), 250)
        case .tall: min(max(size.height * 0.2, 190), 250)
        case .compact: min(max(size.height * 0.23, 150), 190)
        case .short: 118
        }
    }

    @ViewBuilder
    private func content(_ mode: Mode, size: CGSize) -> some View {
        switch mode {
        case .wide, .short:
            HStack(spacing: 0) {
                AlgorithmPanel(compact: mode == .short)
                    .frame(width: mode == .short ? min(320, size.width * 0.4) : min(max(size.width * 0.36, 360), 480))
                Theme.line.frame(width: 1)
                DetailPanel(page: $page, pages: [.operators, .motion, .effects],
                            columns: size.width >= 1100 ? 8 : 4, wideEffects: mode == .wide)
            }
        case .tall:
            VStack(spacing: 0) {
                AlgorithmPanel()
                    .frame(height: min(max(size.height * 0.34, 340), 420))
                Theme.line.frame(height: 1)
                DetailPanel(page: $page, pages: [.operators, .motion, .effects], columns: 8, wideEffects: true)
            }
        case .compact:
            DetailPanel(page: $page, pages: Page.allCases, columns: 4, wideEffects: false)
        }
    }

    // MARK: Launch arguments (for screenshots and UI tests)

    /// `-openfm.demo level|ratio|feedback|envelope|effects` freezes the interface mid-gesture so the highlighted state can be captured.
    private func applyLaunchArguments() {
        switch LaunchOptions.value("demo") {
        case "level": model.beginEditing(.op(6, .level))
        case "ratio": model.beginEditing(.op(2, .coarse))
        case "feedback": model.beginEditing(.feedback)
        case "envelope":
            model.beginEditing(.op(1, .level2), with: [.op(1, .rate2)])
            model.setReadout(title: "OP 1 · ENVELOPE STAGE 2", value: "R28 L80")
        case "effects": model.beginEditing(.delayTime, with: [.delayFeedback])
        case "tone":
            model.beginEditing(Macro.tone)
            model.set(Macro.tone, to: 0.36)
        case "peek": model.peek(Macro.attack)
        default: break
        }
    }

    private static var initialPage: Page {
        LaunchOptions.value("page").flatMap { name in Page.allCases.first { $0.rawValue.lowercased() == name.lowercased() || "\($0)" == name.lowercased() } }
            ?? .operators
    }
}

/// Page tabs and the scrolling editor below them.
private struct DetailPanel: View {
    @Binding var page: RootView.Page
    let pages: [RootView.Page]
    let columns: Int
    let wideEffects: Bool

    var body: some View {
        let current = pages.contains(page) ? page : pages[0]
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(pages, id: \.self) { p in
                    Button {
                        page = p
                        Haptics.tick()
                    } label: {
                        Text(p.rawValue)
                            .labelStyle(10, color: current == p ? Theme.text : Theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(alignment: .bottom) {
                                (current == p ? Theme.accent : Color.clear).frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(current == p ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Theme.gutter)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pages")
            Theme.line.frame(height: 1)

            if current == .algorithm {
                AlgorithmPanel()
            } else {
                ScrollView {
                    Group {
                        switch current {
                        case .operators: OperatorPage(columns: columns)
                        case .motion: MotionPage(columns: columns)
                        default: EffectsPage(wide: wideEffects)
                        }
                    }
                    .padding(Theme.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
