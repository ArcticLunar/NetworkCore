// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol NetworkStreamReconnectControlling: Sendable {
    func awaitReconnectReadiness() async throws
    func reconnectDidSucceed() async
    func reconnectDidFail(with error: Error) async
}

public actor DefaultNetworkStreamReconnectController: NetworkStreamReconnectControlling {
    private let reachabilityMonitor: (any NetworkReachabilityMonitor)?
    private let reachabilityRequirement: NetworkReachabilityRequirement
    private let circuitBreaker: CircuitBreaker?
    private let endpointFailureTracker: EndpointFailureTracker?
    private let context: NetworkRequestContext
    private let circuitOpenPollInterval: TimeInterval
    private let transitionHandler: (@Sendable (CircuitBreakerTransitionMetadata) -> Void)?

    private var pendingAdmission: EndpointFailureTracker.Admission?

    public init(
        reachabilityMonitor: (any NetworkReachabilityMonitor)? = nil,
        reachabilityRequirement: NetworkReachabilityRequirement = .any,
        circuitBreaker: CircuitBreaker? = nil,
        endpointFailureTracker: EndpointFailureTracker? = nil,
        context: NetworkRequestContext,
        circuitOpenPollInterval: TimeInterval = 0.1,
        transitionHandler: (@Sendable (CircuitBreakerTransitionMetadata) -> Void)? = nil
    ) {
        self.reachabilityMonitor = reachabilityMonitor
        self.reachabilityRequirement = reachabilityRequirement
        self.circuitBreaker = circuitBreaker
        self.endpointFailureTracker = endpointFailureTracker
        self.context = context
        self.circuitOpenPollInterval = max(circuitOpenPollInterval, 0)
        self.transitionHandler = transitionHandler
    }

    public func awaitReconnectReadiness() async throws {
        try await awaitReachableNetworkIfNeeded()
        try await awaitCircuitBreakerAdmissionIfNeeded()
    }

    public func reconnectDidSucceed() async {
        guard let pendingAdmission,
              let endpointFailureTracker else {
            return
        }

        let previousState = await endpointFailureTracker.currentState(for: context)
        await endpointFailureTracker.recordSuccess(pendingAdmission)
        let currentState = await endpointFailureTracker.currentState(for: context)
        notifyTransitionIfNeeded(from: previousState, to: currentState)
        self.pendingAdmission = nil
    }

    public func reconnectDidFail(with error: Error) async {
        guard let pendingAdmission,
              let circuitBreaker,
              let endpointFailureTracker else {
            return
        }

        let previousState = await endpointFailureTracker.currentState(for: context)
        await endpointFailureTracker.recordFailure(
            error,
            admission: pendingAdmission,
            circuitBreaker: circuitBreaker
        )
        let currentState = await endpointFailureTracker.currentState(for: context)
        notifyTransitionIfNeeded(from: previousState, to: currentState)
        self.pendingAdmission = nil
    }

    private func awaitReachableNetworkIfNeeded() async throws {
        guard let reachabilityMonitor else {
            return
        }

        let currentStatus = await reachabilityMonitor.currentPathStatus()
        guard reachabilityRequirement.isSatisfied(by: currentStatus) == false else {
            return
        }

        guard await reachabilityMonitor.waitUntilSatisfied(
            reachabilityRequirement,
            timeout: nil
        ) != nil else {
            throw CancellationError()
        }
    }

    private func awaitCircuitBreakerAdmissionIfNeeded() async throws {
        guard let circuitBreaker,
              let endpointFailureTracker else {
            pendingAdmission = nil
            return
        }

        while true {
            do {
                let previousState = await endpointFailureTracker.currentState(for: context)
                pendingAdmission = try await endpointFailureTracker.acquireAdmission(
                    for: context,
                    circuitBreaker: circuitBreaker
                )
                let currentState = await endpointFailureTracker.currentState(for: context)
                notifyTransitionIfNeeded(from: previousState, to: currentState)
                return
            } catch let error as NetworkError {
                guard case let .circuitOpen(retryAfter) = error else {
                    throw error
                }

                let delay = max(
                    retryAfter ?? circuitOpenPollInterval,
                    circuitOpenPollInterval
                )

                if delay > 0 {
                    try await Task.sleep(
                        nanoseconds: UInt64(delay * 1_000_000_000)
                    )
                }
            }
        }
    }

    private func notifyTransitionIfNeeded(
        from previousState: CircuitBreakerState,
        to currentState: CircuitBreakerState
    ) {
        guard let metadata = transitionMetadata(
            from: previousState,
            to: currentState
        ) else {
            return
        }

        transitionHandler?(metadata)
    }

    private func transitionMetadata(
        from previousState: CircuitBreakerState,
        to currentState: CircuitBreakerState
    ) -> CircuitBreakerTransitionMetadata? {
        let previousPhase = phase(for: previousState)
        let currentPhase = phase(for: currentState)

        guard previousPhase != currentPhase else {
            return nil
        }

        let trigger: CircuitBreakerTransitionTrigger

        switch (previousPhase, currentPhase) {
        case (.closed, .open):
            trigger = .failureThresholdReached
        case (.open, .halfOpen):
            trigger = .recoveryProbeStarted
        case (.halfOpen, .closed):
            trigger = .recoveryProbeSucceeded
        case (.halfOpen, .open):
            trigger = .recoveryProbeFailed
        default:
            return nil
        }

        return CircuitBreakerTransitionMetadata(
            fromState: previousPhase,
            toState: currentPhase,
            trigger: trigger
        )
    }

    private func phase(for state: CircuitBreakerState) -> CircuitBreakerStatePhase {
        switch state {
        case .closed:
            return .closed
        case .open:
            return .open
        case .halfOpen:
            return .halfOpen
        }
    }
}
