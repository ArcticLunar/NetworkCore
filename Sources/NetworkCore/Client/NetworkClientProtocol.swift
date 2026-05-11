// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol NetworkClientProtocol {
    func request<E: APIEndpoint>(
        _ endpoint: E,
        progressHandler: TransportProgressHandler?
    ) async throws -> E.Response

    func requestData<E: APIEndpoint>(
        _ endpoint: E,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse

    func stream<E: StreamingEndpoint>(
        _ endpoint: E
    ) async -> AsyncThrowingStream<E.Event, Error>

    func openStream<E: StreamingEndpoint>(
        _ endpoint: E
    ) async throws -> NetworkStreamSession<E.Event>
}

public extension NetworkClientProtocol {
    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        try await request(endpoint, progressHandler: nil)
    }

    func requestData<E: APIEndpoint>(_ endpoint: E) async throws -> TransportResponse {
        try await requestData(endpoint, progressHandler: nil)
    }
}
