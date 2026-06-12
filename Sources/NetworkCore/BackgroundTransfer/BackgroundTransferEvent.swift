// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义后台下载对外广播的事件模型。

import Foundation

/// 后台下载任务回执，用于后续查询、暂停或恢复。
public struct BackgroundTransferReceipt: Equatable, Sendable {
    public let identifier: String
    public let destinationURL: URL

    public init(
        identifier: String,
        destinationURL: URL
    ) {
        self.identifier = identifier
        self.destinationURL = destinationURL
    }
}

/// 后台下载完成时保留的 HTTP 响应摘要。
public struct BackgroundTransferResponse: Equatable, Sendable {
    public let statusCode: Int?
    public let headers: [String: String]?

    public init(
        statusCode: Int?,
        headers: [String: String]? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
    }
}

/// 后台下载生命周期事件。
public enum BackgroundTransferEvent: Equatable, Sendable {
    case scheduled(BackgroundTransferReceipt)
    case restored(BackgroundDownloadRecord)
    case paused(BackgroundDownloadRecord)
    case resumed(BackgroundTransferReceipt)
    case progress(
        identifier: String,
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    )
    case completed(
        receipt: BackgroundTransferReceipt,
        response: BackgroundTransferResponse?
    )
    case failed(
        identifier: String,
        reason: BackgroundTransferFailureReason,
        description: String,
        resumeDataAvailable: Bool
    )
}
