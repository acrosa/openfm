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

    public init(synth: SynthModel, presets: PresetStore) {
        self.synth = synth
        self.presets = presets
        Typeface.register()
    }

    public var body: some View {
        RootView()
            .environment(synth)
            .environment(presets)
    }
}
