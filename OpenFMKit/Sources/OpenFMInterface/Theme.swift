// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import CoreText
import SwiftUI
import UIKit

/// Design tokens. Everything on screen sits on a 4 pt grid and uses these
/// colours and type styles, in both light and dark appearance.
enum Theme {
    static let background = Color(light: 0xF2F1ED, dark: 0x09090A)
    static let surface = Color(light: 0xFAF9F6, dark: 0x131315)
    static let raised = Color(light: 0xFFFFFF, dark: 0x222226)
    static let line = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.11, darkAlpha: 0.10)
    static let text = Color(light: 0x121212, dark: 0xF4F3EF)
    static let secondary = Color(light: 0x121212, dark: 0xF4F3EF, lightAlpha: 0.60, darkAlpha: 0.58)
    static let tertiary = Color(light: 0x121212, dark: 0xF4F3EF, lightAlpha: 0.34, darkAlpha: 0.30)
    /// Fluorescent lime on black; a deeper lime on paper, where the bright one
    /// would be unreadable as text.
    static let accent = Color(light: 0x3F7A00, dark: 0xCCFF00)

    /// Outer margin of every panel.
    static let gutter: CGFloat = 20
    /// Space between sections.
    static let sectionGap: CGFloat = 24
    /// Height of a value cell.
    static let cell: CGFloat = 60
    static let radius: CGFloat = 12
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: .dynamic(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha))
    }
}

// MARK: - Type

/// OpenFM is set in Geist Mono, with Geist for sentences. Both are bundled
/// with this module (SIL Open Font License 1.1, see Fonts/OFL.txt) and
/// registered the first time an interface is created.
enum Typeface {
    static let mono = "GeistMono-Regular"
    static let monoMedium = "GeistMono-Medium"
    static let monoSemiBold = "GeistMono-SemiBold"
    static let monoBold = "GeistMono-Bold"
    static let sans = "Geist-Regular"
    static let sansMedium = "Geist-Medium"

    /// Registers the bundled fonts with the process. Safe to call repeatedly.
    static func register() { _ = registered }

    private static let registered: Bool = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        return !urls.isEmpty
    }()

    static func mono(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: monoBold
        case .semibold: monoSemiBold
        case .medium: monoMedium
        default: mono
        }
    }
}

extension Font {
    /// Small capitals for captions and section titles.
    static func label(_ size: CGFloat = 10) -> Font {
        .custom(Typeface.monoMedium, fixedSize: size)
    }

    /// Every value on screen.
    static func value(_ size: CGFloat = 17, weight: Font.Weight = .medium) -> Font {
        .custom(Typeface.mono(weight), fixedSize: size)
    }

    /// Names and large numbers.
    static func display(_ size: CGFloat) -> Font {
        .custom(Typeface.monoBold, fixedSize: size)
    }

    /// Sentences: hints and explanations.
    static func prose(_ size: CGFloat = 13) -> Font {
        .custom(Typeface.sans, fixedSize: size)
    }
}

extension View {
    /// Caption styling: capitals, tracked out, secondary colour.
    func labelStyle(_ size: CGFloat = 10, color: Color = Theme.secondary) -> some View {
        font(.label(size)).kerning(size * 0.06).textCase(.uppercase).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.75)
    }
}

// MARK: - Haptics

/// The instrument's touch vocabulary. Each kind of event has one feel, used
/// everywhere, so the hand learns what it means:
///
/// - `tick`    a value stepped (one unit, one octave, one page)
/// - `detent`  a value passed its resting point (a macro back at zero)
/// - `bump`    a value hit the end of its range
/// - `grab`    a handle or pad was picked up
/// - `tap`     something switched on or off
/// - `key`     a note was struck, harder for louder
/// - `success` / `failure`  an import or save finished
@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    static func tick() { selection.selectionChanged() }
    static func detent() { rigid.impactOccurred(intensity: 0.55) }
    static func bump() { rigid.impactOccurred(intensity: 1) }
    static func grab() { soft.impactOccurred(intensity: 0.8) }
    static func tap() { rigid.impactOccurred(intensity: 0.7) }
    static func success() { notification.notificationOccurred(.success) }
    static func failure() { notification.notificationOccurred(.error) }

    /// - Parameter velocity: 1...127
    static func key(velocity: Int) {
        light.impactOccurred(intensity: 0.35 + 0.65 * CGFloat(min(max(velocity, 1), 127)) / 127)
        light.prepare()
    }

    /// The right feel for a parameter moving from `before` to `after`:
    /// a tick per step (or per twentieth of a continuous range) and a bump
    /// on arriving at either end.
    static func change(_ param: Param, from before: Double, to after: Double) {
        guard before != after else { return }
        if after == param.range.lowerBound || after == param.range.upperBound {
            bump()
        } else if param.isStepped {
            // Long ranges tick every third step so a fast sweep doesn't buzz.
            if param.span <= 32 || Int(after) % 3 == 0 { tick() }
        } else if Int(param.normalized(before) * 20) != Int(param.normalized(after) * 20) {
            tick()
        }
    }
}

// MARK: - Layout pieces

/// A section title on the caption grid, with optional trailing detail.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).labelStyle(10, color: Theme.text)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.value(11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
        .frame(height: 16)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A grid of value cells separated by hairlines.
struct FieldGrid<Content: View>: View {
    let columns: Int
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
            content
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Fills an unused grid position so the hairlines stay regular.
struct FieldSpacer: View {
    var body: some View {
        Theme.surface.frame(height: Theme.cell).accessibilityHidden(true)
    }
}

/// A section that stays folded until asked for. Used for the deeper
/// parameters, so the common ones are not crowded.
struct MoreSection<Content: View>: View {
    let title: String
    var detail: String?
    let content: Content
    @AppStorage private var expanded: Bool

    init(title: String, detail: String? = nil, key: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
        _expanded = AppStorage(wrappedValue: false, "openfm.more.\(key)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                Haptics.tick()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).labelStyle(10, color: Theme.text)
                    Spacer(minLength: 8)
                    if let detail, expanded {
                        Text(detail).font(.value(11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content }
        }
    }
}
