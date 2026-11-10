// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import CoreAudioKit
import OpenFMCore
import OpenFMEngine
import OpenFMInterface
import SwiftUI

/// The AUv3 extension's entry point: creates the audio unit for the host and
/// shows the same interface as the standalone app.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: OpenFMAudioUnit?
    private var hosting: UIViewController?
    private let store = PresetStore()

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 1024, height: 640)
        view.backgroundColor = .systemBackground
        embedInterface()
    }

    /// Hosts may call this before the view loads, and from any thread.
    public nonisolated func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try OpenFMAudioUnit(componentDescription: componentDescription, options: [])
        // Start from the first factory sound; a host restoring a session
        // replaces it through fullState.
        if let first = FactoryPresets.all.first {
            unit.loadPatchData(Data(first.bytes))
            unit.patchName = first.name
            for (param, value) in zip(Param.patchEffects, first.effects.values) {
                unit.setValue(Float(value), forAddress: AUParameterAddress(param.address))
            }
        }
        DispatchQueue.main.async {
            self.audioUnit = unit
            self.embedInterface()
        }
        return unit
    }

    private func embedInterface() {
        guard isViewLoaded, hosting == nil, let audioUnit else { return }
        let model = SynthModel(audioUnit: audioUnit)
        if let first = store.factory.first, model.name == first.patch.name {
            model.category = first.patch.category
            model.presetID = first.id
        }
        // To ship a different interface in the plug-in, change this line.
        let controller = UIHostingController(rootView: ClassicInterface(synth: model, presets: store))
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        hosting = controller
    }
}
