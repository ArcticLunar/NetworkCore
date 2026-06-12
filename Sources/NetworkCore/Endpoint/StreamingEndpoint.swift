// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 SSE 和 WebSocket 流式端点的声明式契约。

import Foundation

/// 描述一个可以打开长连接并持续产出事件的端点。
public protocol StreamingEndpoint {
    /// 调用方最终消费的事件类型。
    associatedtype Event: Sendable

    var path: String { get }
    var method: HTTPMethod { get }
    var task: RequestTask { get }
    var headers: [String: String] { get }
    var authorization: AuthorizationRequirement { get }
    var options: RequestOptions { get }
    var requestEncoder: (any RequestEncoder)? { get }
    var decoder: JSONDecoder { get }
    var decodingPolicy: NetworkDecodingPolicy? { get }
    var streamKind: NetworkStreamKind { get }

    /// 将底层流事件映射成业务事件；返回 `nil` 表示该事件仅用于连接状态或观测。
    func mapStreamEvent(_ event: NetworkStreamEvent) throws -> Event?
}

public extension StreamingEndpoint {
    var method: HTTPMethod { .get }
    var task: RequestTask { .plain }
    var headers: [String: String] { [:] }
    var authorization: AuthorizationRequirement { .inheritGlobal }
    var options: RequestOptions {
        RequestOptions(
            isIdempotent: method.isIdempotentByDefault
        )
    }
    var requestEncoder: (any RequestEncoder)? { nil }
    var decoder: JSONDecoder { JSONCoderFactory.defaultDecoder() }
    var decodingPolicy: NetworkDecodingPolicy? { nil }
}

public extension StreamingEndpoint where Event: Decodable {
    /// 默认把 WebSocket message 或 SSE data 当作 JSON 解码为业务事件。
    func mapStreamEvent(_ event: NetworkStreamEvent) throws -> Event? {
        switch event {
        case let .message(data):
            return try NetworkDecodingSupport.decode(
                Event.self,
                from: data,
                decoder: decoder,
                policy: decodingPolicy ?? .strict
            ).value

        case let .serverSentEvent(sseEvent):
            return try NetworkDecodingSupport.decode(
                Event.self,
                from: Data(sseEvent.data.utf8),
                decoder: decoder,
                policy: decodingPolicy ?? .strict
            ).value

        case .open, .closed:
            return nil
        }
    }
}
