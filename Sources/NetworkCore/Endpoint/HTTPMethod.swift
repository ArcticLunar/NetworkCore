// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

public extension HTTPMethod {
    var isIdempotentByDefault: Bool {
        switch self {
        case .get, .put, .delete, .head:
            return true
        case .post, .patch:
            return false
        }
    }
}
