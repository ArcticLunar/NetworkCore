// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum NetworkLogPhase: String {
    case start
    case retry
    case success
    case failure
    case decodeDegraded = "decode_degraded"
    case circuitBreakerTransition = "circuit_breaker_transition"
    case streamOpen = "stream_open"
    case streamReconnect = "stream_reconnect"
    case streamClosed = "stream_closed"
    case backgroundScheduled = "background_scheduled"
    case backgroundRestored = "background_restored"
    case backgroundPaused = "background_paused"
    case backgroundResumed = "background_resumed"
    case backgroundProgress = "background_progress"
    case backgroundCompleted = "background_completed"
    case backgroundFailed = "background_failed"
}

public struct NetworkLogRecord {
    public let phase: NetworkLogPhase
    public let requestID: String
    public let environment: String
    public let method: HTTPMethod
    public let path: String
    public let statusCode: Int?
    public let retryCount: Int?
    public let retryNumber: Int?
    public let delay: TimeInterval?
    public let duration: TimeInterval?
    public let requestSize: Int?
    public let responseSize: Int?
    public let errorCategory: String?
    public let errorDescription: String?
    public let attributes: [String: String]?
    public let requestHeaders: [String: String]?
    public let responseHeaders: [String: String]?
    public let requestBody: Data?
    public let responseBody: Data?
    public let requestContentType: String?
    public let responseContentType: String?

    public init(
        phase: NetworkLogPhase,
        requestID: String,
        environment: String,
        method: HTTPMethod,
        path: String,
        statusCode: Int? = nil,
        retryCount: Int? = nil,
        retryNumber: Int? = nil,
        delay: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        requestSize: Int? = nil,
        responseSize: Int? = nil,
        errorCategory: String? = nil,
        errorDescription: String? = nil,
        attributes: [String: String]? = nil,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        requestBody: Data? = nil,
        responseBody: Data? = nil,
        requestContentType: String? = nil,
        responseContentType: String? = nil
    ) {
        self.phase = phase
        self.requestID = requestID
        self.environment = environment
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.retryCount = retryCount
        self.retryNumber = retryNumber
        self.delay = delay
        self.duration = duration
        self.requestSize = requestSize
        self.responseSize = responseSize
        self.errorCategory = errorCategory
        self.errorDescription = errorDescription
        self.attributes = attributes
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.requestContentType = requestContentType
        self.responseContentType = responseContentType
    }
}
