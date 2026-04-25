import Foundation

public enum JSONCoderFactory {
    public static func defaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }

    public static func defaultEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}
