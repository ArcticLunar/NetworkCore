// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 NetworkCore 对外暴露的错误分类。

import Foundation

/// 网络请求、校验、解码、鉴权和韧性策略产生的统一错误类型。
public enum NetworkError: Error {
    /// 请求构建失败，关联值保留可读原因。
    case invalidRequest(String)
    /// transport 返回缺失或不符合 HTTP 响应结构。
    case invalidResponse
    /// 设备离线。
    case offline
    /// 请求超时。
    case timeout
    /// 请求被取消。
    case cancelled
    /// DNS 解析失败。
    case dnsFailure(underlying: Error)
    /// 无法连接到目标主机。
    case cannotConnect(underlying: Error)
    /// TLS 握手失败。
    case tlsFailure(underlying: Error)
    /// server trust 校验失败。
    case serverTrustFailure(underlying: Error)
    /// 未被细分的底层 transport 错误。
    case transport(underlying: Error)
    case networkAccessRestricted(NetworkAccessRestrictionReason)
    case circuitOpen(retryAfter: TimeInterval?)
    case httpStatus(code: Int, data: Data)
    case serverError(statusCode: Int, payload: ServerErrorPayload, data: Data)
    case unauthorized
    case business(code: Int, message: String, data: Data)
    case emptyData
    case unacceptableContentType(String?)
    case decoding(underlying: Error, data: Data)
    case retryExhausted(lastError: Error, retryCount: Int)
}
