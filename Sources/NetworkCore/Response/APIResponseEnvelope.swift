import Foundation

public struct APIResponseEnvelope<T: Decodable>: ResponseEnvelope {
    public let code: Int?
    public let message: String?
    public let requestId: String?
    public let traceId: String?
    public let data: T?

    public init(
        code: Int?,
        message: String?,
        requestId: String?,
        traceId: String?,
        data: T?
    ) {
        self.code = code
        self.message = message
        self.requestId = requestId
        self.traceId = traceId
        self.data = data
    }
}
