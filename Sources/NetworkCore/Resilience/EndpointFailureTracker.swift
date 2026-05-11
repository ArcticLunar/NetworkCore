// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public actor EndpointFailureTracker {
    public struct EndpointKey: Hashable, Sendable {
        public let identifier: String

        public init(identifier: String) {
            self.identifier = identifier
        }
    }

    public struct Admission: Sendable {
        public enum Kind: Sendable {
            case closed
            case halfOpenProbe
        }

        public let key: EndpointKey
        public let kind: Kind

        init(key: EndpointKey, kind: Kind) {
            self.key = key
            self.kind = kind
        }
    }

    private var states: [EndpointKey: CircuitBreakerState] = [:]

    public init() {}

    public func acquireAdmission(
        for context: NetworkRequestContext,
        circuitBreaker: CircuitBreaker,
        now: Date = Date()
    ) throws -> Admission {
        let key = EndpointKey(identifier: context.circuitBreakerIdentifier)
        let state = states[key] ?? .closed(consecutiveFailures: 0)

        switch state {
        case .closed:
            return Admission(key: key, kind: .closed)

        case let .open(until):
            guard now >= until else {
                throw NetworkError.circuitOpen(
                    retryAfter: max(until.timeIntervalSince(now), 0)
                )
            }

            states[key] = .halfOpen(activeProbeCount: 1)
            return Admission(key: key, kind: .halfOpenProbe)

        case let .halfOpen(activeProbeCount):
            guard activeProbeCount < circuitBreaker.halfOpenMaxConcurrentProbes else {
                throw NetworkError.circuitOpen(retryAfter: nil)
            }

            states[key] = .halfOpen(activeProbeCount: activeProbeCount + 1)
            return Admission(key: key, kind: .halfOpenProbe)
        }
    }

    public func recordSuccess(_ admission: Admission) {
        states[admission.key] = .closed(consecutiveFailures: 0)
    }

    public func recordFailure(
        _ error: Error,
        admission: Admission,
        circuitBreaker: CircuitBreaker,
        now: Date = Date()
    ) {
        let existingState = states[admission.key] ?? .closed(consecutiveFailures: 0)
        let countsAsFailure = circuitBreaker.shouldCountFailure(error)

        switch admission.kind {
        case .closed:
            guard countsAsFailure else {
                return
            }

            let currentFailures: Int

            switch existingState {
            case let .closed(consecutiveFailures):
                currentFailures = consecutiveFailures
            case .open, .halfOpen:
                currentFailures = 0
            }

            let nextFailures = currentFailures + 1

            if nextFailures >= circuitBreaker.failureThreshold {
                states[admission.key] = .open(
                    until: now.addingTimeInterval(circuitBreaker.openDuration)
                )
            } else {
                states[admission.key] = .closed(
                    consecutiveFailures: nextFailures
                )
            }

        case .halfOpenProbe:
            if countsAsFailure {
                states[admission.key] = .open(
                    until: now.addingTimeInterval(circuitBreaker.openDuration)
                )
            } else {
                states[admission.key] = .closed(consecutiveFailures: 0)
            }
        }
    }

    public func currentState(
        for context: NetworkRequestContext
    ) -> CircuitBreakerState {
        let key = EndpointKey(identifier: context.circuitBreakerIdentifier)
        return states[key] ?? .closed(consecutiveFailures: 0)
    }
}
