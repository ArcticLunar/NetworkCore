// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 表示 circuit breaker 当前状态。

import Foundation

/// Endpoint 级 circuit breaker 状态。
public enum CircuitBreakerState: Equatable, Sendable {
    /// 正常放行请求，并记录连续失败次数。
    case closed(consecutiveFailures: Int)
    /// 暂停放行，直到指定时间后进入 half-open 探测。
    case open(until: Date)
    /// 允许有限探测请求验证服务是否恢复。
    case halfOpen(activeProbeCount: Int)
}
