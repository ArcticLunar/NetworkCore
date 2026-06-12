// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 承载端点级网络行为开关，覆盖 NetworkConfiguration 中的默认值。

import Foundation

/// 单个端点可覆盖的执行选项。
public struct RequestOptions: Equatable, Sendable {
    /// 端点级超时时间；为空时使用全局默认值。
    public var timeout: TimeInterval?
    /// 原生 `URLRequest` 缓存策略覆盖值。
    public var cachePolicy: URLRequest.CachePolicy?
    /// NetworkCore 自定义缓存策略覆盖值。
    public var networkCachePolicy: NetworkCachePolicy?
    /// 缓存数据的业务有效期；为空时由全局配置决定。
    public var cacheTimeToLive: TimeInterval?
    /// 生成缓存 key 时使用的 URL 归一化策略。
    public var cacheKeyStrategy: NetworkCacheKeyStrategy?
    /// metrics 中使用的归一化路径；为空时根据 path 自动归一化。
    public var metricsPath: String?
    /// 流式连接断开后的重连策略。
    public var streamReconnectPolicy: NetworkStreamReconnectPolicy?
    /// 是否允许默认 retry 策略重试该请求。
    public var isIdempotent: Bool
    /// 是否允许 verbose observer 接收该端点的日志类事件。
    public var allowsLogging: Bool
    /// 是否允许记录请求/响应头；为空时使用观测 profile 默认值。
    public var allowsHeaderLogging: Bool?
    /// 是否允许记录请求/响应体；为空时使用观测 profile 默认值。
    public var allowsBodyLogging: Bool?
    /// 端点级 unauthorized 恢复策略。
    public var unauthorizedStrategy: UnauthorizedStrategy?
    /// 端点级网络可达性要求。
    public var reachabilityRequirement: NetworkReachabilityRequirement?
    /// 昂贵网络下允许上传的最大字节数。
    public var maximumUploadSizeOnExpensiveNetwork: Int?
    /// 受限网络下允许上传的最大字节数。
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

    /// 兼容旧版 `requiresObservability` 命名的初始化入口。
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

    /// 默认选项，适用于没有特殊网络行为的端点。
    public static let `default` = RequestOptions()
}
