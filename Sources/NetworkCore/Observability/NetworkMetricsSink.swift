// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol NetworkMetricsSink {
    func incrementCounter(_ name: String, dimensions: [String: String])
    func recordLatency(_ name: String, duration: TimeInterval, dimensions: [String: String])
}
