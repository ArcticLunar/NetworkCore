// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义普通 HTTP 端点的声明式契约。

import Foundation

/// 描述一次可被 `NetworkClient` 执行并解码的 HTTP 请求。
public protocol APIEndpoint {
    /// 端点返回体解码后的业务模型。
    associatedtype Response: Decodable

    /// 相对 `NetworkEnvironment.baseURL` 的路径。
    var path: String { get }
    /// 请求方法。
    var method: HTTPMethod { get }
    /// 请求体、查询参数、上传或下载任务声明。
    var task: RequestTask { get }
    /// 端点级请求头，会覆盖同名默认请求头。
    var headers: [String: String] { get }
    /// 端点的鉴权要求，默认继承全局配置。
    var authorization: AuthorizationRequirement { get }
    /// 端点级超时、缓存、日志、重试和可达性选项。
    var options: RequestOptions { get }
    /// 可接受的响应 `Content-Type` 列表，默认要求 JSON。
    var acceptableContentTypes: [String] { get }
    /// 端点级请求编码器；为空时使用全局编码器。
    var requestEncoder: (any RequestEncoder)? { get }
    /// 响应解码器配置。
    var decoder: JSONDecoder { get }
    /// 端点级安全解码策略；为空时使用全局默认策略。
    var decodingPolicy: NetworkDecodingPolicy? { get }
}

public extension APIEndpoint {
    var headers: [String: String] { [:] }
    var authorization: AuthorizationRequirement { .inheritGlobal }
    var options: RequestOptions {
        RequestOptions(
            isIdempotent: method.isIdempotentByDefault
        )
    }
    var acceptableContentTypes: [String] { ["application/json"] }
    var requestEncoder: (any RequestEncoder)? { nil }
    var decoder: JSONDecoder { JSONCoderFactory.defaultDecoder() }
    var decodingPolicy: NetworkDecodingPolicy? { nil }
}
