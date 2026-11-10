// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Launch arguments used for screenshots and UI tests, e.g.
/// `-openfm.page effects -openfm.preset "Glass Pad"`.
public enum LaunchOptions {
    public static func value(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: "openfm.\(key)")
    }
}
