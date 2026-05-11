// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct NetworkLogger: NetworkObserver {
    private let sink: any NetworkLogSink
    private let redactor: any NetworkRedactor
    private let policy: NetworkLoggingPolicy

    var loggingPolicy: NetworkLoggingPolicy {
        policy
    }

    public init(
        sink: any NetworkLogSink = ConsoleNetworkLogSink(),
        redactor: any NetworkRedactor = DefaultNetworkRedactor(),
        policy: NetworkLoggingPolicy = .debug
    ) {
        self.sink = sink
        self.redactor = redactor
        self.policy = policy
    }

    public func requestDidStart(_ context: NetworkRequestContext) {
        sink.log(
            NetworkLogRecord(
                phase: .start,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path
            )
        )
    }

    public func requestWillRetry(
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error?,
        delay: TimeInterval?
    ) {
        sink.log(
            NetworkLogRecord(
                phase: .retry,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                retryNumber: retryNumber,
                delay: delay,
                errorCategory: error.map(NetworkObservabilitySupport.category(for:)),
                errorDescription: error.map(NetworkObservabilitySupport.safeErrorDescription(for:))
            )
        )
    }

    public func requestDidFinish(_ event: NetworkEvent) {
        sink.log(makeRecord(from: event))
    }

    public func requestDidDegradeDecoding(
        context: NetworkRequestContext,
        warningCount: Int
    ) {
        sink.log(
            NetworkLogRecord(
                phase: .decodeDegraded,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                attributes: [
                    "warning_count": String(warningCount)
                ]
            )
        )
    }

    public func circuitBreakerDidTransition(
        context: NetworkRequestContext,
        metadata: CircuitBreakerTransitionMetadata
    ) {
        sink.log(
            NetworkLogRecord(
                phase: .circuitBreakerTransition,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                attributes: [
                    "from_state": metadata.fromState.rawValue,
                    "to_state": metadata.toState.rawValue,
                    "trigger": metadata.trigger.rawValue
                ]
            )
        )
    }

    public func streamDidOpen(
        context: NetworkRequestContext,
        metadata: NetworkStreamMetadata?
    ) {
        if let reconnect = metadata?.reconnect {
            sink.log(
                NetworkLogRecord(
                    phase: .streamReconnect,
                    requestID: context.requestID,
                    environment: context.environmentName,
                    method: context.method,
                    path: context.path,
                    attributes: [
                        "reconnect_attempt": String(reconnect.attempt),
                        "reconnect_reason": reconnectReasonDescription(reconnect.reason),
                        "gate_wait_duration": String(reconnect.gateWaitDuration),
                        "backoff_delay": String(reconnect.backoffDelay)
                    ]
                )
            )
        }

        sink.log(
            NetworkLogRecord(
                phase: .streamOpen,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: metadata?.statusCode,
                responseHeaders: shouldIncludeResponseHeaders(
                    for: context
                ) ? metadata?.headers.map(redactor.redact(headers:)) : nil,
                responseContentType: NetworkObservabilitySupport.headerValue(
                    "Content-Type",
                    in: metadata?.headers
                )
            )
        )
    }

    public func streamDidFinish(
        context: NetworkRequestContext,
        error: Error?,
        metadata: NetworkStreamEventMetadata
    ) {
        sink.log(
            NetworkLogRecord(
                phase: .streamClosed,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: error.flatMap(NetworkObservabilitySupport.statusCode(from:)),
                duration: metadata.duration,
                errorCategory: error.map(NetworkObservabilitySupport.category(for:)),
                errorDescription: error.map(NetworkObservabilitySupport.safeErrorDescription(for:)),
                attributes: [
                    "event_count": String(metadata.eventCount),
                    "message_count": String(metadata.messageCount),
                    "message_bytes": String(metadata.messageBytes),
                    "close_code": metadata.closeCode.map(String.init) ?? ""
                ]
            )
        )
    }

    private func makeRecord(from event: NetworkEvent) -> NetworkLogRecord {
        switch event {
        case let .success(context, request, response, metadata):
            return NetworkLogRecord(
                phase: .success,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: response.response.statusCode,
                retryCount: metadata.retryCount,
                duration: metadata.duration,
                requestSize: metadata.requestSize,
                responseSize: metadata.responseSize,
                requestHeaders: shouldIncludeRequestHeaders(
                    for: context
                ) ? redactor.redact(headers: request.allHTTPHeaderFields ?? [:]) : nil,
                responseHeaders: shouldIncludeResponseHeaders(
                    for: context
                ) ? redactor.redact(
                    headers: NetworkObservabilitySupport.headers(from: response.response)
                ) : nil,
                requestBody: prepareBody(
                    request.httpBody,
                    contentType: request.value(forHTTPHeaderField: "Content-Type"),
                    mode: policy.requestBodyMode,
                    context: context,
                    isFailure: false
                ),
                responseBody: prepareBody(
                    response.data.isEmpty ? nil : response.data,
                    contentType: response.response.value(forHTTPHeaderField: "Content-Type"),
                    mode: policy.responseBodyMode,
                    context: context,
                    isFailure: false
                ),
                requestContentType: request.value(forHTTPHeaderField: "Content-Type"),
                responseContentType: response.response.value(forHTTPHeaderField: "Content-Type")
            )

        case let .failure(context, request, error, metadata):
            let responseHeaders = NetworkObservabilitySupport.responseHeaders(from: error)
            let requestContentType = request?.value(forHTTPHeaderField: "Content-Type")
            let responseContentType = NetworkObservabilitySupport.headerValue(
                "Content-Type",
                in: responseHeaders
            )

            return NetworkLogRecord(
                phase: .failure,
                requestID: context.requestID,
                environment: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: NetworkObservabilitySupport.statusCode(from: error),
                retryCount: metadata.retryCount,
                duration: metadata.duration,
                requestSize: metadata.requestSize,
                responseSize: metadata.responseSize,
                errorCategory: NetworkObservabilitySupport.category(for: error),
                errorDescription: NetworkObservabilitySupport.safeErrorDescription(for: error),
                requestHeaders: shouldIncludeRequestHeaders(
                    for: context
                ) ? request.map { redactor.redact(headers: $0.allHTTPHeaderFields ?? [:]) } : nil,
                responseHeaders: shouldIncludeResponseHeaders(
                    for: context
                ) ? responseHeaders.map(redactor.redact(headers:)) : nil,
                requestBody: prepareBody(
                    request?.httpBody,
                    contentType: requestContentType,
                    mode: policy.requestBodyMode,
                    context: context,
                    isFailure: true
                ),
                responseBody: prepareBody(
                    NetworkObservabilitySupport.responseBody(from: error),
                    contentType: responseContentType,
                    mode: policy.responseBodyMode,
                    context: context,
                    isFailure: true
                ),
                requestContentType: requestContentType,
                responseContentType: responseContentType
            )
        }
    }

    private func shouldIncludeRequestHeaders(
        for context: NetworkRequestContext
    ) -> Bool {
        context.options.allowsHeaderLogging ?? policy.includesRequestHeaders
    }

    private func shouldIncludeResponseHeaders(
        for context: NetworkRequestContext
    ) -> Bool {
        context.options.allowsHeaderLogging ?? policy.includesResponseHeaders
    }

    private func prepareBody(
        _ body: Data?,
        contentType: String?,
        mode: NetworkLogBodyCaptureMode,
        context: NetworkRequestContext,
        isFailure: Bool
    ) -> Data? {
        guard let body else {
            return nil
        }

        guard shouldCaptureBody(
            mode: mode,
            context: context,
            isFailure: isFailure
        ) else {
            return nil
        }

        let textualBody = sanitizedBody(
            body,
            contentType: contentType
        )

        return truncatedBodyIfNeeded(textualBody)
    }

    private func shouldCaptureBody(
        mode: NetworkLogBodyCaptureMode,
        context: NetworkRequestContext,
        isFailure: Bool
    ) -> Bool {
        guard context.options.allowsBodyLogging ?? true else {
            return false
        }

        switch mode {
        case .none:
            return false
        case .redacted:
            return true
        case .errorsOnly:
            return isFailure
        case .redactedErrorsOnly:
            return isFailure
        }
    }

    private func sanitizedBody(
        _ body: Data,
        contentType: String?
    ) -> Data {
        if isTextualContentType(contentType) {
            return redactor.redact(
                body: body,
                contentType: contentType
            ) ?? body
        }

        return Data(
            "\(policy.binaryBodyPlaceholder) bytes=\(body.count)".utf8
        )
    }

    private func truncatedBodyIfNeeded(_ body: Data) -> Data {
        guard let maximumBodyBytes,
              body.count > maximumBodyBytes else {
            return body
        }

        var truncated = Data(body.prefix(maximumBodyBytes))
        truncated.append(
            Data("...<truncated total_bytes=\(body.count)>".utf8)
        )
        return truncated
    }

    private var maximumBodyBytes: Int? {
        policy.maximumBodyBytes
    }

    private func isTextualContentType(_ contentType: String?) -> Bool {
        let normalized = contentType?.lowercased() ?? ""

        guard normalized.isEmpty == false else {
            return true
        }

        return normalized.contains("json")
            || normalized.contains("+json")
            || normalized.contains("text/")
            || normalized.contains("xml")
            || normalized.contains("application/x-www-form-urlencoded")
    }

    private func reconnectReasonDescription(
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
