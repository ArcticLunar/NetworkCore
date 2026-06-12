// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义框架支持的 HTTP 方法和默认幂等语义。

import Foundation

/// HTTP 请求方法。
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

public extension HTTPMethod {
    /// 默认幂等判断用于保护 retry，避免误重放非幂等写请求。
    var isIdempotentByDefault: Bool {
        switch self {
        case .get, .put, .delete, .head:
            return true
        case .post, .patch:
            return false
        }
    }
}
