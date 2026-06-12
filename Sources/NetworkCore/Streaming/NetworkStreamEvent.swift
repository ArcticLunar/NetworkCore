// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义流式连接类型、重连策略和原始事件模型。

import Foundation

/// 流式连接协议类型。
public enum NetworkStreamKind: Sendable {
    case serverSentEvents
    case webSocket
}

/// 重连 backoff 策略。
public enum NetworkStreamReconnectBackoff: Equatable, Sendable {
    case fixed(delay: TimeInterval, jitterRatio: Double = 0)
    case exponential(
        initialDelay: TimeInterval,
        multiplier: Double = 2,
        maximumDelay: TimeInterval,
        jitterRatio: Double = 0
    )

    public func delay(
        forAttempt attempt: Int,
        randomValue: Double? = nil
    ) -> TimeInterval {
        let normalizedAttempt = max(1, attempt)
        let resolvedRandomValue = min(
            max(randomValue ?? Double.random(in: 0...1), 0),
            1
        )
        let baseDelay: TimeInterval
        let jitterRatio: Double
        let maximumDelay: TimeInterval?

        switch self {
        case let .fixed(delay, configuredJitterRatio):
            baseDelay = max(0, delay)
            jitterRatio = configuredJitterRatio
            maximumDelay = nil

        case let .exponential(
            initialDelay,
            multiplier,
            configuredMaximumDelay,
            configuredJitterRatio
        ):
            let safeInitialDelay = max(0, initialDelay)
            let safeMultiplier = max(1, multiplier)
            let safeMaximumDelay = max(safeInitialDelay, configuredMaximumDelay)
            let exponent = Double(normalizedAttempt - 1)
            baseDelay = min(
                safeInitialDelay * pow(safeMultiplier, exponent),
                safeMaximumDelay
            )
            jitterRatio = configuredJitterRatio
            maximumDelay = safeMaximumDelay
        }

        // jitter 限制在 0...1，避免配置错误导致负延迟或无限放大。
        let safeJitterRatio = min(max(jitterRatio, 0), 1)

        guard baseDelay > 0, safeJitterRatio > 0 else {
            return baseDelay
        }

        let jitter = baseDelay * safeJitterRatio
        let offset = jitter * ((resolvedRandomValue * 2) - 1)
        let jitteredDelay = max(baseDelay + offset, 0)

        if let maximumDelay {
            return min(jitteredDelay, maximumDelay)
        }

        return jitteredDelay
    }
}

/// 重连预算，用于限制某个时间窗口内的重连频率。
public struct NetworkStreamReconnectBudget: Equatable, Sendable {
    public let maximumAttempts: Int
    public let interval: TimeInterval

    public init(
        maximumAttempts: Int,
        interval: TimeInterval
    ) {
        self.maximumAttempts = max(0, maximumAttempts)
        self.interval = max(0, interval)
    }

    public func requiredDelay(
        for timestamps: [Date],
        now: Date = Date()
    ) -> TimeInterval? {
        guard maximumAttempts > 0 else {
            return nil
        }

        guard interval > 0 else {
            return 0
        }

        let windowStart = now.addingTimeInterval(-interval)
        let attemptsInWindow = timestamps
            .filter { $0 >= windowStart }
            .sorted()

        guard attemptsInWindow.count >= maximumAttempts,
              let oldestAttempt = attemptsInWindow.first else {
            return 0
        }

        return max(
            oldestAttempt.addingTimeInterval(interval).timeIntervalSince(now),
            0
        )
    }
}

/// 触发重连的原因。
public enum NetworkStreamReconnectReason: Hashable, Sendable {
    case networkInterruption
    case abnormalClosure
    case serviceRestart
    case normalClosure
    case customCloseCode(Int)
}

/// 流式连接重连策略。
public struct NetworkStreamReconnectPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let backoff: NetworkStreamReconnectBackoff
    public let reasons: Set<NetworkStreamReconnectReason>
    public let budget: NetworkStreamReconnectBudget?

    public init(
        maximumAttempts: Int,
        backoff: NetworkStreamReconnectBackoff = .fixed(delay: 1),
        budget: NetworkStreamReconnectBudget? = nil,
        reasons: Set<NetworkStreamReconnectReason> = [
            .networkInterruption,
            .abnormalClosure,
            .serviceRestart
        ]
    ) {
        self.maximumAttempts = max(0, maximumAttempts)
        self.backoff = backoff
        self.budget = budget
        self.reasons = reasons
    }

    public func delay(
        forAttempt attempt: Int,
        timestamps: [Date] = [],
        now: Date = Date(),
        randomValue: Double? = nil
    ) -> TimeInterval? {
        guard budget?.maximumAttempts != 0 else {
            return nil
        }

        let backoffDelay = backoff.delay(
            forAttempt: attempt,
            randomValue: randomValue
        )
        let budgetDelay = budget?.requiredDelay(
            for: timestamps,
            now: now
        ) ?? 0

        return max(backoffDelay, budgetDelay)
    }
}

/// 流连接打开事件携带的元数据。
public struct NetworkStreamMetadata: Equatable, Sendable {
    public let statusCode: Int?
    public let headers: [String: String]?
    public let reconnect: NetworkStreamReconnectMetadata?

    public init(
        statusCode: Int?,
        headers: [String: String]? = nil,
        reconnect: NetworkStreamReconnectMetadata? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.reconnect = reconnect
    }
}

/// 一次重连打开事件携带的元数据。
public struct NetworkStreamReconnectMetadata: Equatable, Sendable {
    public let attempt: Int
    public let reason: NetworkStreamReconnectReason
    public let gateWaitDuration: TimeInterval
    public let backoffDelay: TimeInterval

    public init(
        attempt: Int,
        reason: NetworkStreamReconnectReason,
        gateWaitDuration: TimeInterval,
        backoffDelay: TimeInterval
    ) {
        self.attempt = max(1, attempt)
        self.reason = reason
        self.gateWaitDuration = max(0, gateWaitDuration)
        self.backoffDelay = max(0, backoffDelay)
    }
}

/// 收到的消息来源类型。
public enum NetworkStreamMessageKind: String, Equatable, Sendable {
    case webSocketMessage = "websocket"
    case serverSentEvent = "sse"
}

/// 收到消息时用于观测的元数据。
public struct NetworkStreamMessageMetadata: Equatable, Sendable {
    public let sequenceNumber: Int
    public let kind: NetworkStreamMessageKind
    public let bytes: Int

    public init(
        sequenceNumber: Int,
        kind: NetworkStreamMessageKind,
        bytes: Int
    ) {
        self.sequenceNumber = sequenceNumber
        self.kind = kind
        self.bytes = bytes
    }
}

/// Server-Sent Events 的单条事件。
public struct ServerSentEvent: Equatable, Sendable {
    public let id: String?
    public let event: String?
    public let data: String
    public let retry: Int?

    public init(
        id: String? = nil,
        event: String? = nil,
        data: String,
        retry: Int? = nil
    ) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

/// 底层流式连接产生的原始事件。
public enum NetworkStreamEvent: Equatable, Sendable {
    case open(metadata: NetworkStreamMetadata?)
    case message(Data)
    case serverSentEvent(ServerSentEvent)
    case closed(code: Int?, reason: Data?)
}
