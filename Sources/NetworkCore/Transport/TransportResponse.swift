// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct TransportResponse: @unchecked Sendable {
    private enum BodyStorage {
        case inMemory(Data)
        case downloadedFile(URL)
    }

    public let request: URLRequest
    public let response: HTTPURLResponse
    public let downloadedFileURL: URL?
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
            return Data()
        }
    }

    public func loadData() throws -> Data {
        switch bodyStorage {
        case .inMemory(let data):
            return data
        case .downloadedFile(let fileURL):
            return try Data(contentsOf: fileURL)
        }
    }
}
