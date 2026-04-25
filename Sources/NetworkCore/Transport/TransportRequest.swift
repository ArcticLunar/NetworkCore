import Foundation

public enum TransportTask: Sendable {
    case request
    case upload(data: Data)
    case download(destination: URL)
    case backgroundDownload(destination: URL, transferIdentifier: String?)
}

public struct TransportRequest: Sendable {
    public let urlRequest: URLRequest
    public let task: TransportTask

    public init(urlRequest: URLRequest, task: TransportTask) {
        self.urlRequest = urlRequest
        self.task = task
    }
}
