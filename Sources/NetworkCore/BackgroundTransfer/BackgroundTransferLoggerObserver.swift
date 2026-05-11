// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct BackgroundTransferLoggerObserver: BackgroundTransferObserver {
    private let sink: any NetworkLogSink
    private let redactor: any NetworkRedactor

    public init(
        sink: any NetworkLogSink = ConsoleNetworkLogSink(),
        redactor: any NetworkRedactor = DefaultNetworkRedactor()
    ) {
        self.sink = sink
        self.redactor = redactor
    }

    public func backgroundTransferDidEmit(_ observation: BackgroundTransferObservation) {
        sink.log(makeRecord(from: observation))
    }

    private func makeRecord(
        from observation: BackgroundTransferObservation
    ) -> NetworkLogRecord {
        let identifier = identifier(from: observation.event)
        let requestID = observation.record?.observability?.requestID
            ?? identifier
            ?? "unknown"
        let environment = observation.record?.observability?.environmentName
            ?? observation.record?.request.url.host
            ?? "unknown"
        let path = observation.record?.observability?.path
            ?? observation.record?.request.url.path
            ?? "unknown"
        let method = HTTPMethod(
            rawValue: observation.record?.observability?.method
                ?? observation.record?.request.method
                ?? HTTPMethod.get.rawValue
        ) ?? .get
        let requestHeaders = observation.record.map {
            redactor.redact(headers: $0.request.headers)
        }

        switch observation.event {
        case .scheduled:
            return NetworkLogRecord(
                phase: .backgroundScheduled,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                attributes: baseAttributes(identifier: identifier),
                requestHeaders: requestHeaders,
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers)
            )

        case .restored:
            return NetworkLogRecord(
                phase: .backgroundRestored,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                attributes: baseAttributes(identifier: identifier),
                requestHeaders: requestHeaders,
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers)
            )

        case .paused:
            return NetworkLogRecord(
                phase: .backgroundPaused,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                duration: observation.duration,
                attributes: baseAttributes(identifier: identifier),
                requestHeaders: requestHeaders,
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers)
            )

        case .resumed:
            return NetworkLogRecord(
                phase: .backgroundResumed,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                attributes: baseAttributes(identifier: identifier),
                requestHeaders: requestHeaders,
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers)
            )

        case let .progress(_, bytesWritten, totalBytesWritten, totalBytesExpected):
            var attributes = baseAttributes(identifier: identifier)
            attributes["bytes_written"] = String(bytesWritten)
            attributes["total_bytes_written"] = String(totalBytesWritten)
            attributes["total_bytes_expected"] = String(totalBytesExpected)
            attributes["has_expected_bytes"] = String(totalBytesExpected > 0)

            return NetworkLogRecord(
                phase: .backgroundProgress,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                responseSize: numericValue(totalBytesWritten),
                attributes: attributes,
                requestHeaders: requestHeaders,
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers)
            )

        case let .completed(_, response):
            return NetworkLogRecord(
                phase: .backgroundCompleted,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                statusCode: response?.statusCode,
                duration: observation.duration,
                attributes: baseAttributes(identifier: identifier),
                requestHeaders: requestHeaders,
                responseHeaders: response.map { redactor.redact(headers: $0.headers ?? [:]) },
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers),
                responseContentType: headerValue("Content-Type", in: response?.headers)
            )

        case let .failed(_, reason, description, resumeDataAvailable):
            var attributes = baseAttributes(identifier: identifier)
            attributes["resume_data_available"] = String(resumeDataAvailable)
            attributes["failure_reason"] = reason.metricsValue

            if let statusCode = reason.statusCode {
                attributes["status_code"] = String(statusCode)
            }

            return NetworkLogRecord(
                phase: .backgroundFailed,
                requestID: requestID,
                environment: environment,
                method: method,
                path: path,
                duration: observation.duration,
                errorCategory: "background_transfer_failed",
                errorDescription: description,
                attributes: attributes,
                requestHeaders: requestHeaders,
                requestContentType: headerValue("Content-Type", in: observation.record?.request.headers)
            )
        }
    }

    private func identifier(from event: BackgroundTransferEvent) -> String? {
        switch event {
        case let .scheduled(receipt),
             let .resumed(receipt),
             let .completed(receipt, _):
            return receipt.identifier

        case let .restored(record),
             let .paused(record):
            return record.identifier

        case let .progress(identifier, _, _, _),
             let .failed(identifier, _, _, _):
            return identifier
        }
    }

    private func baseAttributes(identifier: String?) -> [String: String] {
        guard let identifier else {
            return [:]
        }

        return ["identifier": identifier]
    }

    private func headerValue(
        _ name: String,
        in headers: [String: String]?
    ) -> String? {
        headers?.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private func numericValue(_ value: Int64) -> Int? {
        Int(exactly: value)
    }
}
