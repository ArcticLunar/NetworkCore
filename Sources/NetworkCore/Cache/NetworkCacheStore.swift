// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 NetworkCore 缓存读写抽象和 URLCache 默认实现。

import Foundation

/// 请求缓存 store。
public protocol NetworkCacheStore: Sendable {
    /// 读取请求对应的缓存响应。
    func cachedResponse(for request: URLRequest) -> NetworkCachedResponse?
    /// 写入缓存响应，并记录存储时间用于 TTL 判断。
    func store(
        _ response: TransportResponse,
        for request: URLRequest,
        storagePolicy: URLCache.StoragePolicy,
        storedAt: Date
    )
    /// 移除请求对应的缓存响应。
    func removeCachedResponse(for request: URLRequest)
}

/// 带存储时间的缓存响应。
public struct NetworkCachedResponse: Sendable {
    public let response: TransportResponse
    public let storedAt: Date

    public init(response: TransportResponse, storedAt: Date = Date()) {
        self.response = response
        self.storedAt = storedAt
    }
}

/// 基于 `URLCache` 的默认缓存 store。
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
            // 下载和后台任务不写入 URLCache，避免把文件型响应误存成内存数据。
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
