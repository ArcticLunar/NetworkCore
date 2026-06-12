// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 封装 transport 返回的 HTTP 响应、body 和下载文件位置。

import Foundation

/// transport 层原始响应。
public struct TransportResponse: @unchecked Sendable {
    private enum BodyStorage {
        case inMemory(Data)
        case downloadedFile(URL)
    }

    /// 原始请求。
    public let request: URLRequest
    /// HTTP 响应元数据。
    public let response: HTTPURLResponse
    /// 下载响应的落盘文件；普通响应为空。
    public let downloadedFileURL: URL?
    /// 后台下载的任务回执；非后台下载为空。
    public let backgroundTransferReceipt: BackgroundTransferReceipt?

    private let bodyStorage: BodyStorage

    public init(
        request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        downloadedFileURL: URL? = nil,
        backgroundTransferReceipt: BackgroundTransferReceipt? = nil
    ) {
        self.request = request
        self.response = response
        self.downloadedFileURL = downloadedFileURL
        self.backgroundTransferReceipt = backgroundTransferReceipt

        if let downloadedFileURL {
            bodyStorage = .downloadedFile(downloadedFileURL)
        } else {
            bodyStorage = .inMemory(data)
        }
    }

    public var data: Data {
        switch bodyStorage {
        case .inMemory(let data):
            return data
        case .downloadedFile:
            // 下载响应默认不把文件读回内存，避免大文件下载完成后造成内存尖峰。
            return Data()
        }
    }

    /// 显式读取响应 body；下载响应会从落盘文件读取。
    public func loadData() throws -> Data {
        switch bodyStorage {
        case .inMemory(let data):
            return data
        case .downloadedFile(let fileURL):
            return try Data(contentsOf: fileURL)
        }
    }
}
