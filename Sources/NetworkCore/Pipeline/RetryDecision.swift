// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum RetryDecision {
    case retry(after: TimeInterval?)
    case retryWith(URLRequest, after: TimeInterval?)
    case retryExhausted
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
