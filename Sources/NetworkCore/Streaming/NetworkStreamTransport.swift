import Foundation

public protocol NetworkStreamTransport: Sendable {
    func openConnection(
        _ request: TransportRequest,
        kind: NetworkStreamKind,
        context: NetworkRequestContext,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) async throws -> any NetworkStreamConnection
}

public final class DefaultNetworkStreamTransport: NetworkStreamTransport, @unchecked Sendable {
    private let sseClient: SSEClient
    private let webSocketClient: WebSocketClient

    public init(
        sseClient: SSEClient = SSEClient(),
        webSocketClient: WebSocketClient = WebSocketClient()
    ) {
        self.sseClient = sseClient
        self.webSocketClient = webSocketClient
    }

    public func openConnection(
        _ request: TransportRequest,
        kind: NetworkStreamKind,
        context: NetworkRequestContext,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) async throws -> any NetworkStreamConnection {
        switch kind {
        case .serverSentEvents:
            return sseClient.connect(
                request.urlRequest,
                reconnectPolicy: context.options.streamReconnectPolicy,
                reconnectController: reconnectController
            )

        case .webSocket:
            return webSocketClient.connect(
                request.urlRequest,
                reconnectPolicy: context.options.streamReconnectPolicy,
                reconnectController: reconnectController
            )
        }
    }
}
