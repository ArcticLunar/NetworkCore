import Foundation

public struct NetworkMetricsObserver: NetworkObserver {
    private let sink: any NetworkMetricsSink
    private let dimensionsPolicy: NetworkMetricsDimensionsPolicy

    public var delivery: NetworkObserverDelivery { .always }

    public init(
        sink: any NetworkMetricsSink,
        dimensionsPolicy: NetworkMetricsDimensionsPolicy = .default
    ) {
        self.sink = sink
        self.dimensionsPolicy = dimensionsPolicy
    }

    public func requestDidStart(_ context: NetworkRequestContext) {
        sink.incrementCounter(
            "network.request.count",
            dimensions: baseDimensions(for: context)
        )
    }

    public func requestWillRetry(
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error?,
        delay: TimeInterval?
    ) {
        var dimensions = baseDimensions(for: context)
        dimensions["retry_number"] = String(retryNumber)

        if let error {
            dimensions["error_category"] = NetworkObservabilitySupport.category(for: error)
        }

        sink.incrementCounter(
            "network.retry.count",
            dimensions: dimensions
        )
    }

    public func requestDidFinish(_ event: NetworkEvent) {
        switch event {
        case let .success(context, _, response, metadata):
            var dimensions = baseDimensions(for: context)
            dimensions["status_code"] = String(response.response.statusCode)

            sink.incrementCounter(
                "network.success.count",
                dimensions: dimensions
            )
            sink.recordLatency(
                "network.request.latency",
                duration: metadata.duration,
                dimensions: dimensions
            )

        case let .failure(context, _, error, metadata):
            var dimensions = baseDimensions(for: context)
            dimensions["error_category"] = NetworkObservabilitySupport.category(for: error)

            if let statusCode = NetworkObservabilitySupport.statusCode(from: error) {
                dimensions["status_code"] = String(statusCode)
            }

            sink.incrementCounter(
                "network.failure.count",
                dimensions: dimensions
            )
            sink.recordLatency(
                "network.request.latency",
                duration: metadata.duration,
                dimensions: dimensions
            )

            if case .timeout = ErrorMapper.map(error) {
                sink.incrementCounter(
                    "network.timeout.count",
                    dimensions: dimensions
                )
            }

            if case .decoding = ErrorMapper.map(error) {
                sink.incrementCounter(
                    "network.decode_failure.count",
                    dimensions: dimensions
                )
            }

            if NetworkObservabilitySupport.isUnauthorized(error) {
                sink.incrementCounter(
                    "network.401.count",
                    dimensions: dimensions
                )
            }
        }
    }

    public func requestDidDegradeDecoding(
        context: NetworkRequestContext,
        warningCount: Int
    ) {
        var dimensions = baseDimensions(for: context)
        dimensions["warning_count"] = String(warningCount)

        sink.incrementCounter(
            "network.decode_degraded.count",
            dimensions: dimensions
        )
    }

    public func circuitBreakerDidTransition(
        context: NetworkRequestContext,
        metadata: CircuitBreakerTransitionMetadata
    ) {
        sink.incrementCounter(
            "network.circuit_breaker.transition.count",
            dimensions: baseDimensions(for: context).merging([
                "from_state": metadata.fromState.rawValue,
                "to_state": metadata.toState.rawValue,
                "trigger": metadata.trigger.rawValue
            ]) { _, new in new }
        )
    }

    public func streamDidOpen(
        context: NetworkRequestContext,
        metadata: NetworkStreamMetadata?
    ) {
        var dimensions = baseDimensions(for: context)

        if let statusCode = metadata?.statusCode {
            dimensions["status_code"] = String(statusCode)
        }

        sink.incrementCounter(
            "network.stream.open.count",
            dimensions: dimensions
        )

        if let reconnect = metadata?.reconnect {
            var reconnectDimensions = dimensions
            reconnectDimensions["reconnect_reason"] = reconnectReasonDimension(
                reconnect.reason
            )
            reconnectDimensions["reconnect_attempt"] = String(reconnect.attempt)

            sink.incrementCounter(
                "network.stream.reconnect.count",
                dimensions: reconnectDimensions
            )
            sink.recordLatency(
                "network.stream.reconnect.gate_wait",
                duration: reconnect.gateWaitDuration,
                dimensions: reconnectDimensions
            )
            sink.recordLatency(
                "network.stream.reconnect.backoff_delay",
                duration: reconnect.backoffDelay,
                dimensions: reconnectDimensions
            )
        }
    }

    public func streamDidReceiveMessage(
        context: NetworkRequestContext,
        metadata: NetworkStreamMessageMetadata
    ) {
        var dimensions = baseDimensions(for: context)
        dimensions["stream_kind"] = metadata.kind.rawValue
        dimensions["sequence_number"] = String(metadata.sequenceNumber)

        sink.incrementCounter(
            "network.stream.message.received.count",
            dimensions: dimensions
        )
        sink.incrementCounter(
            "network.stream.message.bytes",
            dimensions: dimensions.merging([
                "value": String(metadata.bytes)
            ]) { _, new in new }
        )
    }

    public func streamDidFinish(
        context: NetworkRequestContext,
        error: Error?,
        metadata: NetworkStreamEventMetadata
    ) {
        var dimensions = baseDimensions(for: context)
        dimensions["close_code"] = metadata.closeCode.map(String.init) ?? ""

        if let error {
            dimensions["error_category"] = NetworkObservabilitySupport.category(for: error)

            if let statusCode = NetworkObservabilitySupport.statusCode(from: error) {
                dimensions["status_code"] = String(statusCode)
            }

            sink.incrementCounter(
                "network.stream.failure.count",
                dimensions: dimensions
            )
        } else {
            sink.incrementCounter(
                "network.stream.success.count",
                dimensions: dimensions
            )
        }

        sink.recordLatency(
            "network.stream.duration",
            duration: metadata.duration,
            dimensions: dimensions
        )
        sink.incrementCounter(
            "network.stream.message.count",
            dimensions: dimensions.merging([
                "value": String(metadata.messageCount)
            ]) { _, new in new }
        )
    }

    private func baseDimensions(for context: NetworkRequestContext) -> [String: String] {
        dimensionsPolicy.sanitize([
            "environment": context.environmentName,
            "method": context.method.rawValue,
            "path": context.metricsPath
        ])
    }

    private func reconnectReasonDimension(
        _ reason: NetworkStreamReconnectReason
    ) -> String {
        switch reason {
        case .networkInterruption:
            return "network_interruption"
        case .abnormalClosure:
            return "abnormal_closure"
        case .serviceRestart:
            return "service_restart"
        case .normalClosure:
            return "normal_closure"
        case .customCloseCode(let code):
            return "close_\(code)"
        }
    }
}
