// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OpenFMCore
import OpenFMEngine

final class AlgorithmTests: XCTestCase {
    /// The diagram must be drawn from the same table the engine plays.
    func testFlagTableMatchesEngine() {
        for algorithm in 0..<32 {
            for slot in 0..<6 {
                XCTAssertEqual(Algorithm.flagTable[algorithm][slot],
                               OpenFMAudioUnit.algorithmFlags(algorithm, slot: slot),
                               "algorithm \(algorithm + 1) slot \(slot)")
            }
        }
    }

    func testEveryAlgorithmIsWellFormed() {
        XCTAssertEqual(Algorithm.all.count, 32)
        for algorithm in Algorithm.all {
            XCTAssertFalse(algorithm.carriers.isEmpty, "algorithm \(algorithm.number) has no carrier")
            XCTAssertEqual(Set(algorithm.positions.map { "\($0.x),\($0.y)" }).count, 6,
                           "algorithm \(algorithm.number) stacks two operators on one spot")
            for op in 1...6 where !algorithm.isCarrier(op) {
                XCTAssertFalse(algorithm.targets(of: op).isEmpty,
                               "algorithm \(algorithm.number): OP \(op) goes nowhere")
            }
            for edge in algorithm.edges {
                XCTAssertGreaterThan(algorithm.positions[edge.from - 1].y, algorithm.positions[edge.to - 1].y,
                                     "algorithm \(algorithm.number): modulator must sit above its target")
            }
        }
    }

    func testKnownRoutings() {
        let one = Algorithm.number(1)
        XCTAssertEqual(one.carriers, [1, 3])
        XCTAssertEqual(Set(one.edges), [.init(from: 2, to: 1), .init(from: 6, to: 5), .init(from: 5, to: 4), .init(from: 4, to: 3)])
        XCTAssertEqual(one.feedback, .init(from: 6, to: 6))
        XCTAssertEqual(one.downstream(of: 6), [6, 5, 4, 3])

        XCTAssertEqual(Algorithm.number(32).carriers, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(Algorithm.number(5).carriers, [1, 3, 5])
        XCTAssertEqual(Set(Algorithm.number(22).targets(of: 6)), [3, 4, 5])
        // Algorithms 4 and 6 loop feedback through several operators.
        XCTAssertEqual(Algorithm.number(4).feedback, .init(from: 4, to: 6))
        XCTAssertEqual(Algorithm.number(4).feedbackOps, [4, 5, 6])
        XCTAssertEqual(Algorithm.number(6).feedback, .init(from: 5, to: 6))
    }

    func testPreviewOfInitVoiceIsASine() {
        let wave = Algorithm.previewWave(bytes: Patch().bytes, samples: 64)
        XCTAssertEqual(wave.count, 64)
        for (i, sample) in wave.enumerated() {
            XCTAssertEqual(Double(sample), sin(2 * .pi * Double(i) / 64), accuracy: 0.01)
        }
    }
}
