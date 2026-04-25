import Foundation

public struct JSONRequestEncoder: RequestEncoder {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONCoderFactory.defaultEncoder()) {
        self.encoder = encoder
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}
