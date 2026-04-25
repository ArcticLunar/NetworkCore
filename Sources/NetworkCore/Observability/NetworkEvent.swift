import Foundation

public struct NetworkEventMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let retryCount: Int
    public let requestSize: Int?
    public let responseSize: Int?

    public init(
        duration: TimeInterval,
        retryCount: Int,
        requestSize: Int? = nil,
        responseSize: Int? = nil
    ) {
        self.duration = duration
        self.retryCount = retryCount
        self.requestSize = requestSize
        self.responseSize = responseSize
    }
}

public struct NetworkStreamEventMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let eventCount: Int
    public let messageCount: Int
    public let messageBytes: Int
    public let closeCode: Int?

    public init(
        duration: TimeInterval,
        eventCount: Int,
        messageCount: Int,
        messageBytes: Int,
        closeCode: Int? = nil
    ) {
        self.duration = duration
        self.eventCount = eventCount
        self.messageCount = messageCount
        self.messageBytes = messageBytes
        self.closeCode = closeCode
    }
}

public enum CircuitBreakerStatePhase: String, Equatable, Sendable {
    case closed
    case open
    case halfOpen = "half_open"
}

public enum CircuitBreakerTransitionTrigger: String, Equatable, Sendable {
    case failureThresholdReached = "failure_threshold_reached"
    case recoveryProbeStarted = "recovery_probe_started"
    case recoveryProbeSucceeded = "recovery_probe_succeeded"
    case recoveryProbeFailed = "recovery_probe_failed"
}

public struct CircuitBreakerTransitionMetadata: Equatable, Sendable {
    public let fromState: CircuitBreakerStatePhase
    public let toState: CircuitBreakerStatePhase
    public let trigger: CircuitBreakerTransitionTrigger

    public init(
        fromState: CircuitBreakerStatePhase,
        toState: CircuitBreakerStatePhase,
        trigger: CircuitBreakerTransitionTrigger
    ) {
        self.fromState = fromState
        self.toState = toState
        self.trigger = trigger
    }
}

public enum NetworkEvent {
    case success(
        context: NetworkRequestContext,
        request: URLRequest,
        response: TransportResponse,
        metadata: NetworkEventMetadata
    )
    case failure(
        context: NetworkRequestContext,
        request: URLRequest?,
        error: Error,
        metadata: NetworkEventMetadata
    )
}
