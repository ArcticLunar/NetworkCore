// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol ResponseInterceptor {
    func didReceive(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) async throws
}
