// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 metrics 输出端口。

import Foundation

/// 接收 NetworkCore 产生的计数器和耗时指标。
public protocol NetworkMetricsSink {
    /// 递增计数器。
    func incrementCounter(_ name: String, dimensions: [String: String])
    /// 记录耗时指标。
    func recordLatency(_ name: String, duration: TimeInterval, dimensions: [String: String])
}
