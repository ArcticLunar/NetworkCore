// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义后台下载事件的 observer 和 metrics 实现。

import Foundation

/// 后台下载 observer 接收到的事件上下文。
public struct BackgroundTransferObservation: Sendable {
    public let event: BackgroundTransferEvent
    public let record: BackgroundDownloadRecord?
    public let duration: TimeInterval?

    public init(
        event: BackgroundTransferEvent,
        record: BackgroundDownloadRecord?,
        duration: TimeInterval? = nil
    ) {
        self.event = event
        self.record = record
        self.duration = duration
    }
}

/// 监听后台下载生命周期事件。
public protocol BackgroundTransferObserver {
    /// 每当后台下载产生事件时调用。
    func backgroundTransferDidEmit(_ observation: BackgroundTransferObservation)
}

/// 将后台下载事件转换成 metrics。
public struct BackgroundTransferMetricsObserver: BackgroundTransferObserver {
    private let sink: any NetworkMetricsSink

    public init(sink: any NetworkMetricsSink) {
        self.sink = sink
    }

    public func backgroundTransferDidEmit(_ observation: BackgroundTransferObservation) {
        switch observation.event {
        case .scheduled:
            sink.incrementCounter(
                "network.background_transfer.scheduled.count",
                dimensions: dimensions(for: observation)
            )

        case .restored:
            sink.incrementCounter(
                "network.background_transfer.restored.count",
                dimensions: dimensions(for: observation)
            )

        case .paused:
            sink.incrementCounter(
                "network.background_transfer.paused.count",
                dimensions: dimensions(for: observation)
            )

        case .resumed:
            sink.incrementCounter(
                "network.background_transfer.resumed.count",
                dimensions: dimensions(for: observation)
            )

        case let .progress(_, _, _, totalBytesExpected):
            var progressDimensions = dimensions(for: observation)
            progressDimensions["has_expected_bytes"] = String(totalBytesExpected > 0)

            sink.incrementCounter(
                "network.background_transfer.progress.count",
                dimensions: progressDimensions
            )

        case let .completed(_, response):
            var completionDimensions = dimensions(for: observation)

            if let statusCode = response?.statusCode {
                completionDimensions["status_code"] = String(statusCode)
            }

            sink.incrementCounter(
                "network.background_transfer.completed.count",
                dimensions: completionDimensions
            )
            recordLatencyIfAvailable(
                observation.duration,
                dimensions: completionDimensions
            )

        case let .failed(_, reason, _, resumeDataAvailable):
            var failureDimensions = dimensions(for: observation)
            failureDimensions["resume_data_available"] = String(resumeDataAvailable)
            failureDimensions["failure_reason"] = reason.metricsValue

            if let statusCode = reason.statusCode {
                failureDimensions["status_code"] = String(statusCode)
            }

            sink.incrementCounter(
                "network.background_transfer.failed.count",
                dimensions: failureDimensions
            )
            recordLatencyIfAvailable(
                observation.duration,
                dimensions: failureDimensions
            )
        }
    }

    private func dimensions(
        for observation: BackgroundTransferObservation
    ) -> [String: String] {
        var dimensions: [String: String]

        if let record = observation.record {
            dimensions = [
                "environment": record.observability?.environmentName
                    ?? record.request.url.host
                    ?? "unknown",
                "method": record.observability?.method
                    ?? record.request.method,
                "path": record.observability?.path
                    ?? record.request.url.path,
                "identifier": record.identifier
            ]
        } else {
            dimensions = [
                "environment": "unknown",
                "method": "unknown",
                "path": "unknown"
            ]
        }

        switch observation.event {
        case let .progress(identifier, _, _, _),
             let .failed(identifier, _, _, _):
            dimensions["identifier"] = identifier

        case let .scheduled(receipt),
             let .resumed(receipt),
             let .completed(receipt, _):
            dimensions["identifier"] = receipt.identifier

        case let .restored(record),
             let .paused(record):
            dimensions["identifier"] = record.identifier
        }

        return dimensions
    }

    private func recordLatencyIfAvailable(
        _ duration: TimeInterval?,
        dimensions: [String: String]
    ) {
        guard let duration else {
            return
        }

        sink.recordLatency(
            "network.background_transfer.duration",
            duration: duration,
            dimensions: dimensions
        )
    }
}
