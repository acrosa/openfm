// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OpenFMCore
import OpenFMEngine

final class PatchTests: XCTestCase {
    func testInitPatchMatchesEngineInitVoice() {
        XCTAssertEqual(Patch().bytes, [UInt8](OpenFMAudioUnit.initialPatchData()))
    }

    func testFactoryPatchesSurviveByteAndJSONRoundTrips() throws {
        XCTAssertGreaterThanOrEqual(FactoryPresets.all.count, 16)
        XCTAssertEqual(Set(FactoryPresets.all.map(\.name)).count, FactoryPresets.all.count, "names must be unique")
        for patch in FactoryPresets.all {
            XCTAssertEqual(patch.operators.count, 6, patch.name)
            let viaBytes = Patch(bytes: patch.bytes, name: patch.name, category: patch.category, effects: patch.effects)
            XCTAssertEqual(viaBytes, patch, patch.name)
            let viaJSON = try JSONDecoder().decode(Patch.self, from: JSONEncoder().encode(patch))
            XCTAssertEqual(viaJSON, patch, patch.name)
        }
    }

    func testOperatorOrderInBytes() {
        var patch = Patch()
        patch.operators[0].level = 11   // OP1 is the last block of a DX7 voice
        patch.operators[5].level = 66   // OP6 is the first
        patch.operators[2].on = false
        let bytes = patch.bytes
        XCTAssertEqual(bytes[105 + 16], 11)
        XCTAssertEqual(bytes[16], 66)
        XCTAssertEqual(bytes[155], 0b110111)
        XCTAssertEqual(Param.op(1, .level).address, 121)
        XCTAssertEqual(Param.op(6, .level).address, 16)
    }

    // MARK: SysEx

    /// Packs a 156-byte voice into the 128-byte bulk layout, the inverse of
    /// `SysEx.unpack`.
    private func pack(_ v: [UInt8]) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 128)
        for op in 0..<6 {
            let s = op * 21, d = op * 17
            for k in 0..<11 { p[d + k] = v[s + k] }
            p[d + 11] = v[s + 11] | (v[s + 12] << 2)
            p[d + 12] = v[s + 13] | (v[s + 20] << 3)
            p[d + 13] = v[s + 14] | (v[s + 15] << 2)
            p[d + 14] = v[s + 16]
            p[d + 15] = v[s + 17] | (v[s + 18] << 1)
            p[d + 16] = v[s + 19]
        }
        for k in 0..<9 { p[102 + k] = v[126 + k] }
        p[111] = v[135] | (v[136] << 3)
        for k in 0..<4 { p[112 + k] = v[137 + k] }
        p[116] = v[141] | (v[142] << 1) | (v[143] << 4)
        for k in 0..<11 { p[117 + k] = v[144 + k] }
        return p
    }

    func testBulkDumpImport() throws {
        var dump: [UInt8] = [0xF0, 0x43, 0x00, 0x09, 0x20, 0x00]
        let sources = (0..<32).map { FactoryPresets.all[$0 % FactoryPresets.all.count] }
        for patch in sources { dump += pack(patch.bytes) }
        dump += [0x00, 0xF7]
        XCTAssertEqual(dump.count, 4104)

        let imported = try SysEx.patches(from: Data(dump), category: "Bank")
        XCTAssertEqual(imported.count, 32)
        for (source, result) in zip(sources, imported) {
            // A cartridge keeps neither operator switches nor effects.
            var expected = source.bytes
            expected[155] = 0x3F
            XCTAssertEqual(result.bytes, expected, source.name)
            XCTAssertEqual(result.name, String(source.name.uppercased().prefix(10)).trimmingCharacters(in: .whitespaces))
            XCTAssertEqual(result.category, "Bank")
        }
    }

    func testSingleVoiceAndHeaderlessImport() throws {
        let patch = FactoryPresets.all[0]
        let single: [UInt8] = [0xF0, 0x43, 0x00, 0x00, 0x01, 0x1B] + patch.bytes.prefix(155) + [0x00, 0xF7]
        let one = try SysEx.patches(from: Data(single), category: "Single")
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].algorithm, patch.algorithm)

        let raw = (0..<32).flatMap { _ in pack(patch.bytes) }
        XCTAssertEqual(try SysEx.patches(from: Data(raw), category: "Raw").count, 32)
    }

    func testGarbageIsRejectedAndDirtyDataIsClamped() {
        XCTAssertThrowsError(try SysEx.patches(from: Data([1, 2, 3, 4]), category: "x"))
        XCTAssertThrowsError(try SysEx.patches(from: Data(), category: "x"))
        let dirty = SysEx.unpack([UInt8](repeating: 0x7F, count: 128))
        XCTAssertLessThanOrEqual(dirty[134], 31)
        XCTAssertLessThanOrEqual(dirty[16], 99)
        XCTAssertLessThanOrEqual(dirty[144], 48)
    }
}
