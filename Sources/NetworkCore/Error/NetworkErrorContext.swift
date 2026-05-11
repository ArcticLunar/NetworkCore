// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct NetworkErrorContext: Equatable {
    public let requestID: String
    public let environmentName: String
    public let method: HTTPMethod
    public let path: String
    public let statusCode: Int?
    public let duration: TimeInterval?
    public let retryCount: Int
    public let responseHeaders: [String: String]?

    public init(
        requestID: String,
        environmentName: String,
        method: HTTPMethod,
        path: String,
        statusCode: Int?,
        duration: TimeInterval?,
        retryCount: Int,
        responseHeaders: [String: String]? = nil
    ) {
        self.requestID = requestID
        self.environmentName = environmentName
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.duration = duration
        self.retryCount = retryCount
        self.responseHeaders = responseHeaders
    }
}
