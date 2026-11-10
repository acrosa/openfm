// swift-tools-version: 6.0
// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

// OpenFM in three layers. Dependencies only point downwards:
//
//   OpenFMInterface / OpenFMMinimalInterface / your interface   (SwiftUI)
//                        │
//                   OpenFMCore        Swift: parameters, patches, presets, audio + MIDI hosting
//                        │
//                   OpenFMEngine      C++ / Objective-C++: DSP and the AUAudioUnit
//
// An interface imports OpenFMCore and nothing else.
let package = Package(
    name: "OpenFMKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "OpenFMCore", targets: ["OpenFMCore"]),
        .library(name: "OpenFMInterface", targets: ["OpenFMInterface"]),
        .library(name: "OpenFMMinimalInterface", targets: ["OpenFMMinimalInterface"]),
    ],
    targets: [
        .target(
            name: "OpenFMEngine",
            exclude: ["msfa/LICENSE"],
            cSettings: [.headerSearchPath("."), .headerSearchPath("msfa")],
            cxxSettings: [.headerSearchPath("."), .headerSearchPath("msfa")],
            linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("AVFoundation"), .linkedFramework("CoreMIDI")]
        ),
        .target(name: "OpenFMCore", dependencies: ["OpenFMEngine"]),
        // Fonts/ holds Geist and Geist Mono (SIL Open Font License 1.1).
        .target(name: "OpenFMInterface", dependencies: ["OpenFMCore"], resources: [.copy("Fonts")]),
        .target(name: "OpenFMMinimalInterface", dependencies: ["OpenFMCore"]),
        .testTarget(name: "OpenFMCoreTests", dependencies: ["OpenFMCore"]),
    ],
    cxxLanguageStandard: .cxx20
)
