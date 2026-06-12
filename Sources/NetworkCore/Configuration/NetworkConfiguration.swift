// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 汇总 NetworkClient 执行请求所需的全局依赖和默认策略。

import Foundation

/// NetworkCore 的运行时配置对象。
public struct NetworkConfiguration {
    /// 后端环境和 baseURL。
    public let environment: NetworkEnvironment
    /// 所有请求默认携带的请求头。
    public let defaultHeaders: [String: String]
    /// 请求和资源默认超时时间。
    public let defaultTimeout: TimeInterval
    public let defaultCachePolicy: URLRequest.CachePolicy
    public let defaultNetworkCachePolicy: NetworkCachePolicy
    public let defaultCacheTimeToLive: TimeInterval?
    public let defaultCacheKeyStrategy: NetworkCacheKeyStrategy
    /// 未被端点覆盖时使用的默认鉴权要求。
    public let defaultAuthorizationRequirement: AuthorizationRequirement
    public let requestEncoder: any RequestEncoder
    public let requestInterceptors: [any RequestInterceptor]
    public let responseInterceptors: [any ResponseInterceptor]
    public let responseValidators: [any ResponseValidator]
    public let businessValidator: (any BusinessResponseValidator)?
    public let serverErrorDecoder: ServerErrorDecoder
    public let responseDecoder: any ResponseDecoder
    public let defaultDecodingPolicy: NetworkDecodingPolicy
    /// retry 策略按数组顺序评估，首个需要重试或耗尽的决策会生效。
    public let retryPolicies: [any RetryPolicy]
    public let observers: [any NetworkObserver]
    public let cacheStore: (any NetworkCacheStore)?
    public let reachabilityMonitor: (any NetworkReachabilityMonitor)?
    public let reachabilityRequirement: NetworkReachabilityRequirement
    public let unsatisfiedPathBehavior: ReachabilityUnsatisfiedBehavior
    public let maximumUploadSizeOnExpensiveNetwork: Int?
    public let maximumUploadSizeOnConstrainedNetwork: Int?
    public let appLifecycleMonitor: any NetworkAppLifecycleMonitor
    public let circuitBreaker: CircuitBreaker?
    public let endpointFailureTracker: EndpointFailureTracker?

    public init(
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
        observers: [any NetworkObserver] = [],
        cacheStore: (any NetworkCacheStore)? = URLCacheNetworkCacheStore(),
        reachabilityMonitor: (any NetworkReachabilityMonitor)? = nil,
        reachabilityRequirement: NetworkReachabilityRequirement = .any,
        unsatisfiedPathBehavior: ReachabilityUnsatisfiedBehavior = .failFast,
        maximumUploadSizeOnExpensiveNetwork: Int? = nil,
        maximumUploadSizeOnConstrainedNetwork: Int? = nil,
        circuitBreaker: CircuitBreaker? = nil,
        endpointFailureTracker: EndpointFailureTracker? = nil,
        appLifecycleMonitor: any NetworkAppLifecycleMonitor = AlwaysActiveNetworkAppLifecycleMonitor()
    ) {
        self.environment = environment
        self.defaultHeaders = defaultHeaders
        self.defaultTimeout = defaultTimeout
        self.defaultCachePolicy = defaultCachePolicy
        self.defaultNetworkCachePolicy = defaultNetworkCachePolicy
        self.defaultCacheTimeToLive = defaultCacheTimeToLive
        self.defaultCacheKeyStrategy = defaultCacheKeyStrategy
        self.defaultAuthorizationRequirement = defaultAuthorizationRequirement
        self.requestEncoder = requestEncoder
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.businessValidator = businessValidator
        self.serverErrorDecoder = serverErrorDecoder
        // 默认先校验 HTTP 状态，再处理空响应和 Content-Type，避免错误包体被误解码。
        self.responseValidators = responseValidators ?? [
            HTTPStatusCodeValidator(serverErrorDecoder: serverErrorDecoder),
            EmptyDataValidator(),
            ContentTypeValidator()
        ]
        self.responseDecoder = responseDecoder
        self.defaultDecodingPolicy = defaultDecodingPolicy
        self.retryPolicies = retryPolicies
        self.observers = observers
        self.cacheStore = cacheStore
        self.reachabilityMonitor = reachabilityMonitor
        self.reachabilityRequirement = reachabilityRequirement
        self.unsatisfiedPathBehavior = unsatisfiedPathBehavior
        self.maximumUploadSizeOnExpensiveNetwork = maximumUploadSizeOnExpensiveNetwork
        self.maximumUploadSizeOnConstrainedNetwork = maximumUploadSizeOnConstrainedNetwork
        self.appLifecycleMonitor = appLifecycleMonitor
        self.circuitBreaker = circuitBreaker
        // 只要启用 circuit breaker，就自动提供 failure tracker，降低接入门槛。
        self.endpointFailureTracker = endpointFailureTracker
            ?? circuitBreaker.map { _ in EndpointFailureTracker() }
    }
}
