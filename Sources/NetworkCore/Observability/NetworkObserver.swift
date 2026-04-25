import Foundation

public enum NetworkObserverDelivery {
    case always
    case verbose
}

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
