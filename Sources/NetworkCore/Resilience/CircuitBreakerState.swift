import Foundation

public enum CircuitBreakerState: Equatable, Sendable {
    case closed(consecutiveFailures: Int)
    case open(until: Date)
    case halfOpen(activeProbeCount: Int)
}
