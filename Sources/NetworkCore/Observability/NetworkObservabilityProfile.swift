// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义日志采集策略、metrics 维度策略和默认观测 profile。

import Foundation

/// 日志中 body 的采集模式。
public enum NetworkLogBodyCaptureMode: Equatable, Sendable {
    case none
    case redacted
    case errorsOnly
    case redactedErrorsOnly
}

/// 控制请求/响应头和 body 是否进入日志。
public struct NetworkLoggingPolicy: Equatable, Sendable {
    public let includesRequestHeaders: Bool
    public let includesResponseHeaders: Bool
    public let requestBodyMode: NetworkLogBodyCaptureMode
    public let responseBodyMode: NetworkLogBodyCaptureMode
    public let maximumBodyBytes: Int?
    public let binaryBodyPlaceholder: String

    public init(
        includesRequestHeaders: Bool = true,
        includesResponseHeaders: Bool = true,
        requestBodyMode: NetworkLogBodyCaptureMode = .redacted,
        responseBodyMode: NetworkLogBodyCaptureMode = .redacted,
        maximumBodyBytes: Int? = 16_384,
        binaryBodyPlaceholder: String = "<omitted binary body>"
    ) {
        self.includesRequestHeaders = includesRequestHeaders
        self.includesResponseHeaders = includesResponseHeaders
        self.requestBodyMode = requestBodyMode
        self.responseBodyMode = responseBodyMode
        self.maximumBodyBytes = maximumBodyBytes.map { max($0, 0) }
        self.binaryBodyPlaceholder = binaryBodyPlaceholder
    }

    public static let debug = NetworkLoggingPolicy(
        includesRequestHeaders: true,
        includesResponseHeaders: true,
        requestBodyMode: .redacted,
        responseBodyMode: .redacted,
        maximumBodyBytes: 16_384
    )

    public static let staging = NetworkLoggingPolicy(
        includesRequestHeaders: true,
        includesResponseHeaders: true,
        requestBodyMode: .redactedErrorsOnly,
        responseBodyMode: .redacted,
        maximumBodyBytes: 8_192
    )

    public static let release = NetworkLoggingPolicy(
        includesRequestHeaders: true,
        includesResponseHeaders: true,
        requestBodyMode: .none,
        responseBodyMode: .redactedErrorsOnly,
        maximumBodyBytes: 2_048
    )
}

/// 控制 metrics 维度值的长度，避免高基数或超长标签污染上报。
public struct NetworkMetricsDimensionsPolicy: Equatable, Sendable {
    public let maximumValueLength: Int?

    public init(maximumValueLength: Int? = 128) {
        self.maximumValueLength = maximumValueLength.map { max($0, 1) }
    }

    public static let `default` = NetworkMetricsDimensionsPolicy()
    public static let debug = NetworkMetricsDimensionsPolicy(maximumValueLength: 256)
    public static let staging = NetworkMetricsDimensionsPolicy(maximumValueLength: 128)
    public static let release = NetworkMetricsDimensionsPolicy(maximumValueLength: 96)

    func sanitize(_ dimensions: [String: String]) -> [String: String] {
        guard let maximumValueLength else {
            return dimensions
        }

        return dimensions.reduce(into: [:]) { partialResult, item in
            if item.value.count > maximumValueLength {
                partialResult[item.key] = String(item.value.prefix(maximumValueLength))
            } else {
                partialResult[item.key] = item.value
            }
        }
    }
}

/// 组合日志和 metrics 维度策略的观测 profile。
public struct NetworkObservabilityProfile {
    public let logger: NetworkLogger?
    public let metricsDimensionsPolicy: NetworkMetricsDimensionsPolicy

    public init(
        logger: NetworkLogger?,
        metricsDimensionsPolicy: NetworkMetricsDimensionsPolicy = .default
    ) {
        self.logger = logger
        self.metricsDimensionsPolicy = metricsDimensionsPolicy
    }

    public static func debug(
        sink: any NetworkLogSink = ConsoleNetworkLogSink(enabled: true),
        redactor: any NetworkRedactor = DefaultNetworkRedactor(),
        loggingPolicy: NetworkLoggingPolicy = .debug
    ) -> NetworkObservabilityProfile {
        NetworkObservabilityProfile(
            logger: NetworkLogger(
                sink: sink,
                redactor: redactor,
                policy: loggingPolicy
            ),
            metricsDimensionsPolicy: .debug
        )
    }

    public static func staging(
        sink: any NetworkLogSink = ConsoleNetworkLogSink(enabled: true),
        redactor: any NetworkRedactor = DefaultNetworkRedactor(),
        loggingPolicy: NetworkLoggingPolicy = .staging
    ) -> NetworkObservabilityProfile {
        NetworkObservabilityProfile(
            logger: NetworkLogger(
                sink: sink,
                redactor: redactor,
                policy: loggingPolicy
            ),
            metricsDimensionsPolicy: .staging
        )
    }

    public static func release(
        sink: any NetworkLogSink = ConsoleNetworkLogSink(enabled: false),
        redactor: any NetworkRedactor = DefaultNetworkRedactor(),
        loggingPolicy: NetworkLoggingPolicy = .release
    ) -> NetworkObservabilityProfile {
        NetworkObservabilityProfile(
            logger: NetworkLogger(
                sink: sink,
                redactor: redactor,
                policy: loggingPolicy
            ),
            metricsDimensionsPolicy: .release
        )
    }
}
