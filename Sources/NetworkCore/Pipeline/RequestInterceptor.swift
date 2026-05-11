// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol RequestInterceptor {
    func adapt(
        _ request: URLRequest,
        context: NetworkRequestContext
    ) async throws -> URLRequest
}
