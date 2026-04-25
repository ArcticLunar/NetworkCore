import Alamofire
import Foundation

public enum NetworkBuildConfiguration: String, Equatable {
    case debug
    case release

    public static var current: NetworkBuildConfiguration {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

public struct NetworkProductionObservers {
    public let logger: NetworkLogger?
    public let metricsSink: (any NetworkMetricsSink)?
    public let metricsDimensionsPolicy: NetworkMetricsDimensionsPolicy
    public let additionalObservers: [any NetworkObserver]

    public init(
        logger: NetworkLogger? = nil,
        metricsSink: (any NetworkMetricsSink)? = nil,
        metricsDimensionsPolicy: NetworkMetricsDimensionsPolicy? = nil,
        additionalObservers: [any NetworkObserver] = [],
        buildConfiguration: NetworkBuildConfiguration = .current
    ) {
        let profile = NetworkDefaults.defaultProductionObservabilityProfile(
            buildConfiguration: buildConfiguration
        )

        self.logger = logger ?? profile.logger
        self.metricsSink = metricsSink
        self.metricsDimensionsPolicy = metricsDimensionsPolicy
            ?? profile.metricsDimensionsPolicy
        self.additionalObservers = additionalObservers
    }

    public init(
        profile: NetworkObservabilityProfile,
        metricsSink: (any NetworkMetricsSink)? = nil,
        additionalObservers: [any NetworkObserver] = []
    ) {
        self.init(
            logger: profile.logger,
            metricsSink: metricsSink,
            metricsDimensionsPolicy: profile.metricsDimensionsPolicy,
            additionalObservers: additionalObservers
        )
    }
}

public enum NetworkDefaults {
    public static func makeSession(
        timeout: TimeInterval = 15,
        eventMonitors: [any EventMonitor] = [],
        baseURL: URL? = nil,
        securityPolicy: NetworkSecurityPolicy? = nil
    ) -> Session {
        let resolvedSecurityPolicy = securityPolicy
            ?? baseURL.map { defaultSecurityPolicy(for: $0) }
            ?? .systemDefault()

        return AlamofireSessionFactory.makeSession(
            timeout: timeout,
            eventMonitors: eventMonitors,
            securityPolicy: resolvedSecurityPolicy
        )
    }

    public static func defaultSecurityPolicy(
        for baseURL: URL,
        buildConfiguration: NetworkBuildConfiguration = .current
    ) -> NetworkSecurityPolicy {
        guard let host = baseURL.host else {
            return .systemDefault()
        }

        switch buildConfiguration {
        case .debug:
            return .systemDefault(
                hosts: [host],
                allHostsMustBeEvaluated: false
            )

        case .release:
            return .systemDefault(
                hosts: [host],
                allHostsMustBeEvaluated: true
            )
        }
    }

    public static func makeProductionConfiguration(
        environment: NetworkEnvironment,
        defaultHeaders: [String: String] = [:],
        defaultTimeout: TimeInterval = 15,
        defaultCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        defaultNetworkCachePolicy: NetworkCachePolicy = .useProtocolCachePolicy,
        defaultCacheTimeToLive: TimeInterval? = nil,
        defaultCacheKeyStrategy: NetworkCacheKeyStrategy = .normalizeQueryItems,
        defaultAuthorizationRequirement: AuthorizationRequirement = .bearerToken,
        requestEncoder: any RequestEncoder = JSONRequestEncoder(),
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = [],
        responseValidators: [any ResponseValidator]? = nil,
        businessValidator: (any BusinessResponseValidator)? = nil,
        serverErrorDecoder: ServerErrorDecoder = ServerErrorDecoder(),
        responseDecoder: any ResponseDecoder = SafeJSONResponseDecoder(),
        defaultDecodingPolicy: NetworkDecodingPolicy = .strict,
        retryPolicies: [any RetryPolicy] = [
            DefaultRetryPolicy()
        ],
        observers: NetworkProductionObservers = NetworkProductionObservers(
            profile: defaultProductionObservabilityProfile()
        ),
        cacheStore: (any NetworkCacheStore)? = URLCacheNetworkCacheStore(),
        reachabilityMonitor: (any NetworkReachabilityMonitor)? = nil,
        reachabilityRequirement: NetworkReachabilityRequirement = .any,
        unsatisfiedPathBehavior: ReachabilityUnsatisfiedBehavior = .failFast,
        maximumUploadSizeOnExpensiveNetwork: Int? = nil,
        maximumUploadSizeOnConstrainedNetwork: Int? = nil,
        circuitBreaker: CircuitBreaker? = nil,
        endpointFailureTracker: EndpointFailureTracker? = nil,
        appLifecycleMonitor: any NetworkAppLifecycleMonitor = AlwaysActiveNetworkAppLifecycleMonitor()
    ) -> NetworkConfiguration {
        NetworkConfiguration(
            environment: environment,
            defaultHeaders: defaultHeaders,
            defaultTimeout: defaultTimeout,
            defaultCachePolicy: defaultCachePolicy,
            defaultNetworkCachePolicy: defaultNetworkCachePolicy,
            defaultCacheTimeToLive: defaultCacheTimeToLive,
            defaultCacheKeyStrategy: defaultCacheKeyStrategy,
            defaultAuthorizationRequirement: defaultAuthorizationRequirement,
            requestEncoder: requestEncoder,
            requestInterceptors: requestInterceptors,
            responseInterceptors: responseInterceptors,
            responseValidators: responseValidators,
            businessValidator: businessValidator,
            serverErrorDecoder: serverErrorDecoder,
            responseDecoder: responseDecoder,
            defaultDecodingPolicy: defaultDecodingPolicy,
            retryPolicies: retryPolicies,
            observers: makeProductionObservers(from: observers),
            cacheStore: cacheStore,
            reachabilityMonitor: reachabilityMonitor,
            reachabilityRequirement: reachabilityRequirement,
            unsatisfiedPathBehavior: unsatisfiedPathBehavior,
            maximumUploadSizeOnExpensiveNetwork: maximumUploadSizeOnExpensiveNetwork,
            maximumUploadSizeOnConstrainedNetwork: maximumUploadSizeOnConstrainedNetwork,
            circuitBreaker: circuitBreaker,
            endpointFailureTracker: endpointFailureTracker,
            appLifecycleMonitor: appLifecycleMonitor
        )
    }

    public static func makeProductionClient(
        configuration: NetworkConfiguration,
        eventMonitors: [any EventMonitor] = [],
        securityPolicy: NetworkSecurityPolicy? = nil,
        backgroundDownloadManager: BackgroundDownloadManager? = nil,
        streamTransport: (any NetworkStreamTransport)? = nil
    ) -> NetworkClient {
        let session = makeSession(
            timeout: configuration.defaultTimeout,
            eventMonitors: eventMonitors,
            baseURL: configuration.environment.baseURL,
            securityPolicy: securityPolicy
        )

        return NetworkClient(
            configuration: configuration,
            transport: AlamofireTransport(
                session: session,
                backgroundDownloadManager: backgroundDownloadManager
            ),
            streamTransport: streamTransport
        )
    }

    public static func defaultBackgroundDownloadSessionIdentifier(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        suffix: String = "NetworkCoreBackgroundDownload"
    ) -> String {
        let resolvedBundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let resolvedBundleIdentifier,
              resolvedBundleIdentifier.isEmpty == false else {
            return "NetworkCore.\(suffix)"
        }

        return "\(resolvedBundleIdentifier).\(suffix)"
    }

    public static func defaultProductionObservabilityProfile(
        buildConfiguration: NetworkBuildConfiguration = .current
    ) -> NetworkObservabilityProfile {
        switch buildConfiguration {
        case .debug:
            return .debug()
        case .release:
            return .release()
        }
    }

    private static func makeProductionObservers(
        from preset: NetworkProductionObservers
    ) -> [any NetworkObserver] {
        var resolvedObservers: [any NetworkObserver] = []

        if let logger = preset.logger {
            resolvedObservers.append(logger)
        }

        if let metricsSink = preset.metricsSink {
            resolvedObservers.append(
                NetworkMetricsObserver(
                    sink: metricsSink,
                    dimensionsPolicy: preset.metricsDimensionsPolicy
                )
            )
        }

        resolvedObservers.append(contentsOf: preset.additionalObservers)
        return resolvedObservers
    }
}
