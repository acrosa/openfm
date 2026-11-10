// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Reads Yamaha DX7 voice data: 32-voice bulk dumps (the usual 4104-byte
/// `.syx` cartridge file) and single-voice dumps.
public enum SysEx {
    public enum ImportError: LocalizedError {
        case notDX7

        public var errorDescription: String? {
            "This file doesn’t contain DX7 voices. OpenFM reads 32-voice bulk dumps and single-voice dumps."
        }
    }

    public static func patches(from data: Data, category: String) throws -> [Patch] {
        let bytes = [UInt8](data)
        var result: [Patch] = []
        var i = 0
        while i + 6 <= bytes.count {
            guard bytes[i] == 0xF0, bytes[i + 1] == 0x43 else { i += 1; continue }
            let format = bytes[i + 3]
            let count = Int(bytes[i + 4]) << 7 | Int(bytes[i + 5])
            let body = i + 6
            if format == 9, count == 4096, body + 4096 <= bytes.count {
                for v in 0..<32 {
                    let packed = Array(bytes[(body + v * 128)..<(body + (v + 1) * 128)])
                    result.append(Patch(bytes: unpack(packed), category: category))
                }
                i = body + 4096
            } else if format == 0, count == 155, body + 155 <= bytes.count {
                var voice = Array(bytes[body..<(body + 155)])
                voice.append(0x3F)
                result.append(Patch(bytes: sanitized(voice), category: category))
                i = body + 155
            } else {
                i += 1
            }
        }
        // Some files are a bare 4096-byte dump without the SysEx wrapper.
        if result.isEmpty, bytes.count == 4096 {
            for v in 0..<32 {
                result.append(Patch(bytes: unpack(Array(bytes[(v * 128)..<((v + 1) * 128)])), category: category))
            }
        }
        guard !result.isEmpty else { throw ImportError.notDX7 }
        return result
    }

    /// Expands one 128-byte packed bulk voice to the 156-byte edit layout.
    public static func unpack(_ p: [UInt8]) -> [UInt8] {
        var v = [UInt8](repeating: 0, count: Patch.byteCount)
        for op in 0..<6 {
            let s = op * 17, d = op * 21
            for k in 0..<11 { v[d + k] = p[s + k] }
            v[d + 11] = p[s + 11] & 3
            v[d + 12] = (p[s + 11] >> 2) & 3
            v[d + 13] = p[s + 12] & 7
            v[d + 20] = (p[s + 12] >> 3) & 15
            v[d + 14] = p[s + 13] & 3
            v[d + 15] = (p[s + 13] >> 2) & 7
            v[d + 16] = p[s + 14]
            v[d + 17] = p[s + 15] & 1
            v[d + 18] = (p[s + 15] >> 1) & 31
            v[d + 19] = p[s + 16]
        }
        for k in 0..<9 { v[126 + k] = p[102 + k] }
        v[135] = p[111] & 7
        v[136] = (p[111] >> 3) & 1
        for k in 0..<4 { v[137 + k] = p[112 + k] }
        v[141] = p[116] & 1
        v[142] = (p[116] >> 1) & 7
        v[143] = (p[116] >> 4) & 7
        for k in 0..<11 { v[144 + k] = p[117 + k] }
        v[155] = 0x3F
        return sanitized(v)
    }

    /// Clamps every byte to its legal range; real-world dumps are not always clean.
    public static func sanitized(_ voice: [UInt8]) -> [UInt8] {
        var v = voice
        let opMax: [UInt8] = [99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 3, 3, 7, 3, 7, 99, 1, 31, 99, 14]
        for op in 0..<6 {
            for k in 0..<21 { v[op * 21 + k] = min(v[op * 21 + k], opMax[k]) }
        }
        let globalMax: [UInt8] = [99, 99, 99, 99, 99, 99, 99, 99, 31, 7, 1, 99, 99, 99, 99, 1, 5, 7, 48]
        for k in 0..<19 { v[126 + k] = min(v[126 + k], globalMax[k]) }
        return v
    }
}
