import Foundation

public struct RequestOptions: Equatable, Sendable {
    public var timeout: TimeInterval?
    public var cachePolicy: URLRequest.CachePolicy?
    public var networkCachePolicy: NetworkCachePolicy?
    public var cacheTimeToLive: TimeInterval?
    public var cacheKeyStrategy: NetworkCacheKeyStrategy?
    public var metricsPath: String?
    public var streamReconnectPolicy: NetworkStreamReconnectPolicy?
    public var isIdempotent: Bool
    public var allowsLogging: Bool
    public var allowsHeaderLogging: Bool?
    public var allowsBodyLogging: Bool?
    public var unauthorizedStrategy: UnauthorizedStrategy?
    public var reachabilityRequirement: NetworkReachabilityRequirement?
    public var maximumUploadSizeOnExpensiveNetwork: Int?
    public var maximumUploadSizeOnConstrainedNetwork: Int?

    public init(
        timeout: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil,
        networkCachePolicy: NetworkCachePolicy? = nil,
        cacheTimeToLive: TimeInterval? = nil,
        cacheKeyStrategy: NetworkCacheKeyStrategy? = nil,
        metricsPath: String? = nil,
        streamReconnectPolicy: NetworkStreamReconnectPolicy? = nil,
        isIdempotent: Bool = false,
        allowsLogging: Bool = true,
        allowsHeaderLogging: Bool? = nil,
        allowsBodyLogging: Bool? = nil,
        unauthorizedStrategy: UnauthorizedStrategy? = nil,
        reachabilityRequirement: NetworkReachabilityRequirement? = nil,
        maximumUploadSizeOnExpensiveNetwork: Int? = nil,
        maximumUploadSizeOnConstrainedNetwork: Int? = nil
    ) {
        self.timeout = timeout
        self.cachePolicy = cachePolicy
        self.networkCachePolicy = networkCachePolicy
        self.cacheTimeToLive = cacheTimeToLive
        self.cacheKeyStrategy = cacheKeyStrategy
        self.metricsPath = metricsPath
        self.streamReconnectPolicy = streamReconnectPolicy
        self.isIdempotent = isIdempotent
        self.allowsLogging = allowsLogging
        self.allowsHeaderLogging = allowsHeaderLogging
        self.allowsBodyLogging = allowsBodyLogging
        self.unauthorizedStrategy = unauthorizedStrategy
        self.reachabilityRequirement = reachabilityRequirement
        self.maximumUploadSizeOnExpensiveNetwork = maximumUploadSizeOnExpensiveNetwork
        self.maximumUploadSizeOnConstrainedNetwork = maximumUploadSizeOnConstrainedNetwork
    }

    public init(
        timeout: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil,
        networkCachePolicy: NetworkCachePolicy? = nil,
        cacheTimeToLive: TimeInterval? = nil,
        cacheKeyStrategy: NetworkCacheKeyStrategy? = nil,
        metricsPath: String? = nil,
        streamReconnectPolicy: NetworkStreamReconnectPolicy? = nil,
        isIdempotent: Bool = false,
        requiresObservability: Bool,
        allowsHeaderLogging: Bool? = nil,
        allowsBodyLogging: Bool? = nil,
        unauthorizedStrategy: UnauthorizedStrategy? = nil,
        reachabilityRequirement: NetworkReachabilityRequirement? = nil,
        maximumUploadSizeOnExpensiveNetwork: Int? = nil,
        maximumUploadSizeOnConstrainedNetwork: Int? = nil
    ) {
        self.init(
            timeout: timeout,
            cachePolicy: cachePolicy,
            networkCachePolicy: networkCachePolicy,
            cacheTimeToLive: cacheTimeToLive,
            cacheKeyStrategy: cacheKeyStrategy,
            metricsPath: metricsPath,
            streamReconnectPolicy: streamReconnectPolicy,
            isIdempotent: isIdempotent,
            allowsLogging: requiresObservability,
            allowsHeaderLogging: allowsHeaderLogging,
            allowsBodyLogging: allowsBodyLogging,
            unauthorizedStrategy: unauthorizedStrategy,
            reachabilityRequirement: reachabilityRequirement,
            maximumUploadSizeOnExpensiveNetwork: maximumUploadSizeOnExpensiveNetwork,
            maximumUploadSizeOnConstrainedNetwork: maximumUploadSizeOnConstrainedNetwork
        )
    }

    public var requiresObservability: Bool {
        get { allowsLogging }
        set { allowsLogging = newValue }
    }

    public static let `default` = RequestOptions()
}
