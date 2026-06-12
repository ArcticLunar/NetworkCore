// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 表示 retry 策略对当前请求结果给出的处理决定。

import Foundation

/// Retry 策略的执行结果。
public enum RetryDecision {
    /// 使用当前请求重试，可选延迟。
    case retry(after: TimeInterval?)
    /// 使用替换后的 URLRequest 重试，可选延迟。
    case retryWith(URLRequest, after: TimeInterval?)
    /// 符合 retry 条件，但已经达到策略上限。
    case retryExhausted
    /// 不进行 retry。
    case doNotRetry

    var shouldRetry: Bool {
        switch self {
        case .retry, .retryWith:
            return true
        case .retryExhausted, .doNotRetry:
            return false
        }
    }
}
