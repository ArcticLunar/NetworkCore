// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 NetworkCore 自定义缓存策略，并映射到 URLCache 行为。

import Foundation

/// 请求级缓存策略。
public enum NetworkCachePolicy: Equatable, Sendable {
    /// 遵循系统协议缓存策略。
    case useProtocolCachePolicy
    /// 忽略本地缓存，直接请求网络。
    case reloadIgnoringCache
    /// 有可用缓存时返回缓存，否则请求网络。
    case returnCacheElseLoad
    /// 先返回缓存，再在后台重验证。
    case staleWhileRevalidate
    /// 只写入内存缓存。
    case memoryOnly
    /// 允许写入磁盘缓存。
    case disk
    /// 不读取也不写入缓存，并移除已缓存响应。
    case noStore
}

extension NetworkCachePolicy {
    var urlRequestCachePolicy: URLRequest.CachePolicy {
        switch self {
        case .useProtocolCachePolicy:
            return .useProtocolCachePolicy
        case .reloadIgnoringCache:
            return .reloadIgnoringLocalCacheData
        case .returnCacheElseLoad, .memoryOnly, .disk:
            return .returnCacheDataElseLoad
        case .staleWhileRevalidate:
            return .reloadRevalidatingCacheData
        case .noStore:
            return .reloadIgnoringLocalCacheData
        }
    }

    var readsFromCacheStore: Bool {
        switch self {
        case .returnCacheElseLoad, .staleWhileRevalidate, .memoryOnly, .disk:
            return true
        case .useProtocolCachePolicy, .reloadIgnoringCache, .noStore:
            return false
        }
    }

    var writesToCacheStore: Bool {
        storagePolicy != nil
    }

    var storagePolicy: URLCache.StoragePolicy? {
        switch self {
        case .returnCacheElseLoad, .staleWhileRevalidate, .disk:
            return .allowed
        case .memoryOnly:
            return .allowedInMemoryOnly
        case .useProtocolCachePolicy, .reloadIgnoringCache, .noStore:
            return nil
        }
    }

    var refreshesInBackgroundWhenCached: Bool {
        self == .staleWhileRevalidate
    }

    var removesCachedResponse: Bool {
        self == .noStore
    }
}
