// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol RetryPolicy {
    func evaluate(
        request: URLRequest,
        result: Result<TransportResponse, Error>,
        retryCount: Int,
        context: NetworkRequestContext
    ) async -> RetryDecision
}
