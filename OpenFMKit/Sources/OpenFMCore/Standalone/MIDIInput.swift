// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import CoreMIDI
import Foundation
import OpenFMEngine

/// Listens to every connected MIDI source (USB, Bluetooth, network, other
/// apps) and publishes an "OpenFM" virtual destination other apps can play.
public final class MIDIInput: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var destination = MIDIEndpointRef()
    private let lock = NSLock()

    public init(audioUnit: OpenFMAudioUnit) {
        MIDIClientCreateWithBlock("OpenFM" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged { self?.connectAll() }
        }
        // CoreMIDI serialises these callbacks on its own thread, which is the
        // single producer the engine's MIDI queue expects.
        let receive: MIDIReceiveBlock = { list, _ in
            for packet in list.unsafeSequence() {
                for word in packet.words() where word >> 28 == 2 {
                    audioUnit.receiveMIDIStatus(UInt8((word >> 16) & 0xff),
                                                data1: UInt8((word >> 8) & 0x7f),
                                                data2: UInt8(word & 0x7f))
                }
            }
        }
        MIDIInputPortCreateWithProtocol(client, "OpenFM In" as CFString, ._1_0, &port, receive)
        MIDIDestinationCreateWithProtocol(client, "OpenFM" as CFString, ._1_0, &destination, receive)
        connectAll()
    }

    deinit {
        MIDIClientDispose(client)
    }

    private func connectAll() {
        lock.lock()
        defer { lock.unlock() }
        for i in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(port, MIDIGetSource(i), nil)
        }
    }
}
