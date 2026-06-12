// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 NetworkCore 的观测事件订阅接口。

import Foundation

/// Observer 投递策略。
public enum NetworkObserverDelivery {
    /// 始终投递，适合 metrics 等不可丢事件。
    case always
    /// 受端点 logging 开关控制，适合日志。
    case verbose
}

/// 监听请求、流式连接、解码降级和 circuit breaker 事件。
public protocol NetworkObserver {
    var delivery: NetworkObserverDelivery { get }
    func requestDidStart(_ context: NetworkRequestContext)
    func requestWillRetry(
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error?,
        delay: TimeInterval?
    )
    func requestDidFinish(_ event: NetworkEvent)
    func requestDidDegradeDecoding(
        context: NetworkRequestContext,
        warningCount: Int
    )
    func streamDidOpen(
        context: NetworkRequestContext,
        metadata: NetworkStreamMetadata?
    )
    func streamDidReceiveMessage(
        context: NetworkRequestContext,
        metadata: NetworkStreamMessageMetadata
    )
    func streamDidFinish(
        context: NetworkRequestContext,
        error: Error?,
        metadata: NetworkStreamEventMetadata
    )
    func circuitBreakerDidTransition(
        context: NetworkRequestContext,
        metadata: CircuitBreakerTransitionMetadata
    )
}

public extension NetworkObserver {
    /// 默认作为 verbose observer，避免关闭日志时仍产生大量事件。
    var delivery: NetworkObserverDelivery { .verbose }

    func requestWillRetry(
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error?,
        delay: TimeInterval?
    ) {}

    func requestDidDegradeDecoding(
        context: NetworkRequestContext,
        warningCount: Int
    ) {}

    func streamDidOpen(
        context: NetworkRequestContext,
        metadata: NetworkStreamMetadata?
    ) {}

    func streamDidReceiveMessage(
        context: NetworkRequestContext,
        metadata: NetworkStreamMessageMetadata
    ) {}

    func streamDidFinish(
        context: NetworkRequestContext,
        error: Error?,
        metadata: NetworkStreamEventMetadata
    ) {}

    func circuitBreakerDidTransition(
        context: NetworkRequestContext,
        metadata: CircuitBreakerTransitionMetadata
    ) {}
}
