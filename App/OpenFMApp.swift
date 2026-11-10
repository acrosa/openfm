// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import OpenFMCore
import OpenFMInterface
import OpenFMMinimalInterface
import SwiftUI

/// The standalone app is a thin shell: start a session, show an interface.
/// To ship a different interface, change `interface(for:)`.
@main
struct OpenFMApp: App {
    @State private var session = try? OpenFMSession(initialPreset: LaunchOptions.value("preset"))
    @State private var openError: String?

    var body: some Scene {
        WindowGroup {
            if let session {
                Screen { interface(for: session) }
                    .persistentSystemOverlays(.hidden)
                    .task { session.start() }
                    // Patch files opened from Files, AirDrop or another app.
                    .onOpenURL { url in
                        do { try session.open(url) } catch { openError = error.localizedDescription }
                    }
                    .alert("Couldn’t Open File", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(openError ?? "")
                    }
            } else {
                ContentUnavailableView("Audio Unavailable", systemImage: "speaker.slash",
                                       description: Text("OpenFM couldn’t start its sound engine. Close other audio apps and try again."))
            }
        }
    }

    @ViewBuilder
    private func interface(for session: OpenFMSession) -> some View {
        if LaunchOptions.value("interface") == "minimal" {
            MinimalInterface(synth: session.synth, presets: session.presets)
        } else {
            ClassicInterface(synth: session.synth, presets: session.presets, looper: session.looper)
        }
    }
}

/// Screenshot aid: with `-openfm.landscape 1` the interface is laid out
/// sideways, for simulators that can't be rotated from the command line.
private struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if LaunchOptions.value("landscape") != nil {
            GeometryReader { geo in
                content
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        } else {
            content
        }
    }
}
