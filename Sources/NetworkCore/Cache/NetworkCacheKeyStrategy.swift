import Foundation

public enum NetworkCacheKeyStrategy: Equatable, Sendable {
    case request
    case normalizeQueryItems
}
