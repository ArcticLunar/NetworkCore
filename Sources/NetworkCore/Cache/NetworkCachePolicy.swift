import Foundation

public enum NetworkCachePolicy: Equatable, Sendable {
    case useProtocolCachePolicy
    case reloadIgnoringCache
    case returnCacheElseLoad
    case staleWhileRevalidate
    case memoryOnly
    case disk
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
