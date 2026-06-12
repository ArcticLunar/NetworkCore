// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 将结构化网络日志输出到控制台。

import Foundation

/// 默认 console 日志 sink，DEBUG 默认开启，RELEASE 默认关闭。
public struct ConsoleNetworkLogSink: NetworkLogSink {
    private let enabled: Bool

    public init(enabled: Bool? = nil) {
#if DEBUG
        self.enabled = enabled ?? true
#else
        self.enabled = enabled ?? false
#endif
    }

    public func log(_ record: NetworkLogRecord) {
        guard enabled else { return }

        // 输出 JSON 风格 payload，方便本地复制和日志系统解析。
        let payload = serializedPayload(for: record)
        let output: String

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            output = string
        } else {
            output = String(describing: payload)
        }

        print("[Network] \(output)")
    }

    private func serializedPayload(for record: NetworkLogRecord) -> [String: Any] {
        var payload: [String: Any] = [
            "phase": record.phase.rawValue,
            "requestID": record.requestID,
            "environment": record.environment,
            "method": record.method.rawValue,
            "path": record.path
        ]

        if let statusCode = record.statusCode {
            payload["statusCode"] = statusCode
        }

        if let retryCount = record.retryCount {
            payload["retryCount"] = retryCount
        }

        if let retryNumber = record.retryNumber {
            payload["retryNumber"] = retryNumber
        }

        if let delay = record.delay {
            payload["delay"] = delay
        }

        if let duration = record.duration {
            payload["duration"] = duration
        }

        if let requestSize = record.requestSize {
            payload["requestSize"] = requestSize
        }

        if let responseSize = record.responseSize {
            payload["responseSize"] = responseSize
        }

        if let errorCategory = record.errorCategory {
            payload["errorCategory"] = errorCategory
        }

        if let errorDescription = record.errorDescription {
            payload["errorDescription"] = errorDescription
        }

        if let attributes = record.attributes, attributes.isEmpty == false {
            payload["attributes"] = attributes
        }

        if let requestHeaders = record.requestHeaders, requestHeaders.isEmpty == false {
            payload["requestHeaders"] = requestHeaders
        }

        if let responseHeaders = record.responseHeaders, responseHeaders.isEmpty == false {
            payload["responseHeaders"] = responseHeaders
        }

        if let requestBody = renderBody(record.requestBody, contentType: record.requestContentType) {
            payload["requestBody"] = requestBody
        }

        if let responseBody = renderBody(record.responseBody, contentType: record.responseContentType) {
            payload["responseBody"] = responseBody
        }

        return payload
    }

    private func renderBody(_ body: Data?, contentType: String?) -> String? {
        guard let body else { return nil }
        guard body.isEmpty == false else { return "" }

        if let string = String(data: body, encoding: .utf8) {
            return string
        }

        let contentTypeDescription = contentType ?? "unknown"
        return "<binary \(body.count) bytes contentType=\(contentTypeDescription)>"
    }
}
