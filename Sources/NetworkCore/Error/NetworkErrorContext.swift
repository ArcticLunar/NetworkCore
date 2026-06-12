// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 保存错误上抛时需要一起携带的结构化请求信息。

import Foundation

/// 网络失败上下文，用于日志、上报和排障。
public struct NetworkErrorContext: Equatable {
    /// 单次请求唯一标识。
    public let requestID: String
    /// 发生错误的环境名。
    public let environmentName: String
    /// 请求方法。
    public let method: HTTPMethod
    /// 请求 path。
    public let path: String
    /// HTTP 状态码；没有服务端响应时为空。
    public let statusCode: Int?
    /// 从开始请求到失败的耗时。
    public let duration: TimeInterval?
    /// 失败前已经发生的 retry 次数。
    public let retryCount: Int
    /// 响应头快照，便于排查 trace id 或服务端限流信息。
    public let responseHeaders: [String: String]?

    public init(
        requestID: String,
        environmentName: String,
        method: HTTPMethod,
        path: String,
        statusCode: Int?,
        duration: TimeInterval?,
        retryCount: Int,
        responseHeaders: [String: String]? = nil
    ) {
        self.requestID = requestID
        self.environmentName = environmentName
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.duration = duration
        self.retryCount = retryCount
        self.responseHeaders = responseHeaders
    }
}
