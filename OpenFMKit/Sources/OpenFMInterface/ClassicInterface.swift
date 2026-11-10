// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import SwiftUI

/// OpenFM's standard interface. This is the only public type in the module:
/// the app and the AUv3 extension each show one of these, and swapping in a
/// different interface means changing that single line.
public struct ClassicInterface: View {
    private let synth: SynthModel
    private let presets: PresetStore
    private let isPlugIn: Bool

    /// - Parameter isPlugIn: true inside a host. Hosts record what is played
    ///   on their own keyboard, so the built-in one says it is for trying sounds.
    public init(synth: SynthModel, presets: PresetStore, isPlugIn: Bool = false) {
        self.synth = synth
        self.presets = presets
        self.isPlugIn = isPlugIn
        Typeface.register()
    }

    public var body: some View {
        RootView()
            .environment(synth)
            .environment(presets)
            .environment(\.isPlugIn, isPlugIn)
    }
}

extension EnvironmentValues {
    /// True when the interface is running inside a host as an AUv3 plug-in.
    @Entry var isPlugIn = false
}
