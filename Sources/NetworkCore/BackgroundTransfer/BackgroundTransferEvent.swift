import Foundation

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
