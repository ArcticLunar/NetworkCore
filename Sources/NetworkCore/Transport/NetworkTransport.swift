// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol NetworkTransport {
    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse
}

public extension NetworkTransport {
    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext
    ) async throws -> TransportResponse {
        try await send(
            request,
            context: context,
            progressHandler: nil
        )
    }
}
