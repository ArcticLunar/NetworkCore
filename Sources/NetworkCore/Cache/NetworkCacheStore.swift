import Foundation

public protocol NetworkCacheStore: Sendable {
    func cachedResponse(for request: URLRequest) -> NetworkCachedResponse?
    func store(
        _ response: TransportResponse,
        for request: URLRequest,
        storagePolicy: URLCache.StoragePolicy,
        storedAt: Date
    )
    func removeCachedResponse(for request: URLRequest)
}

public struct NetworkCachedResponse: Sendable {
    public let response: TransportResponse
    public let storedAt: Date

    public init(response: TransportResponse, storedAt: Date = Date()) {
        self.response = response
        self.storedAt = storedAt
    }
}

public final class URLCacheNetworkCacheStore: NetworkCacheStore, @unchecked Sendable {
    private static let storedAtKey = "NetworkCore.NetworkCacheStore.StoredAt"
    public let urlCache: URLCache

    public init(urlCache: URLCache = .shared) {
        self.urlCache = urlCache
    }

    public func cachedResponse(for request: URLRequest) -> NetworkCachedResponse? {
        guard let cachedResponse = urlCache.cachedResponse(for: request),
              let httpResponse = cachedResponse.response as? HTTPURLResponse else {
            return nil
        }

        let storedAt =
            cachedResponse.userInfo?[Self.storedAtKey] as? Date
            ?? Date()

        return NetworkCachedResponse(
            response: TransportResponse(
                request: request,
                response: httpResponse,
                data: cachedResponse.data
            ),
            storedAt: storedAt
        )
    }

    public func store(
        _ response: TransportResponse,
        for request: URLRequest,
        storagePolicy: URLCache.StoragePolicy,
        storedAt: Date = Date()
    ) {
        guard response.downloadedFileURL == nil,
              response.backgroundTransferReceipt == nil else {
            return
        }

        let cachedResponse = CachedURLResponse(
            response: response.response,
            data: response.data,
            userInfo: [Self.storedAtKey: storedAt],
            storagePolicy: storagePolicy
        )

        urlCache.storeCachedResponse(cachedResponse, for: request)
    }

    public func removeCachedResponse(for request: URLRequest) {
        urlCache.removeCachedResponse(for: request)
    }
}
