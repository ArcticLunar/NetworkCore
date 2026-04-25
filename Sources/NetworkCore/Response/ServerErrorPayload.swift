import Foundation

public struct ServerErrorPayload: Decodable, Equatable {
    public let code: Int?
    public let message: String?
    public let requestID: String?
    public let traceID: String?

    public init(
        code: Int? = nil,
        message: String? = nil,
        requestID: String? = nil,
        traceID: String? = nil
    ) {
        self.code = code
        self.message = message
        self.requestID = requestID
        self.traceID = traceID
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case msg
        case error
        case requestId
        case requestID = "requestID"
        case requestIdSnake = "request_id"
        case traceId
        case traceID = "traceID"
        case traceIdSnake = "trace_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = Self.decodeInt(container, keys: [.code])
        message = Self.decodeString(container, keys: [.message, .msg, .error])
        requestID = Self.decodeString(container, keys: [.requestId, .requestID, .requestIdSnake])
        traceID = Self.decodeString(container, keys: [.traceId, .traceID, .traceIdSnake])
    }

    var isMeaningful: Bool {
        code != nil || message?.isEmpty == false || requestID?.isEmpty == false || traceID?.isEmpty == false
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let intValue = try? container.decode(Int.self, forKey: key) {
                return intValue
            }

            if let stringValue = try? container.decode(String.self, forKey: key),
               let intValue = Int(stringValue) {
                return intValue
            }
        }

        return nil
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
        }

        return nil
    }
}
