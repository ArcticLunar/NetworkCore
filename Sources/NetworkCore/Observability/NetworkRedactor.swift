import Foundation

public protocol NetworkRedactor {
    func redact(headers: [String: String]) -> [String: String]
    func redact(body: Data?, contentType: String?) -> Data?
}

public struct DefaultNetworkRedactor: NetworkRedactor {
    private let sensitiveHeaderFields: Set<String>
    private let sensitiveBodyFields: Set<String>
    private let redactionPlaceholder: String

    public init(
        sensitiveHeaderFields: Set<String> = [
            "authorization",
            "cookie",
            "set-cookie"
        ],
        sensitiveBodyFields: Set<String> = [
            "refresh_token",
            "refreshToken",
            "access_token",
            "accessToken",
            "password",
            "phone",
            "email"
        ],
        redactionPlaceholder: String = "<redacted>"
    ) {
        self.sensitiveHeaderFields = Set(
            sensitiveHeaderFields.map(Self.normalize(field:))
        )
        self.sensitiveBodyFields = Set(
            sensitiveBodyFields.map(Self.normalize(field:))
        )
        self.redactionPlaceholder = redactionPlaceholder
    }

    public func redact(headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { partialResult, item in
            if sensitiveHeaderFields.contains(Self.normalize(field: item.key)) {
                partialResult[item.key] = redactionPlaceholder
            } else {
                partialResult[item.key] = item.value
            }
        }
    }

    public func redact(body: Data?, contentType: String?) -> Data? {
        guard let body else { return nil }
        guard body.isEmpty == false else { return body }

        let normalizedContentType = contentType?.lowercased() ?? ""

        if normalizedContentType.contains("application/x-www-form-urlencoded") {
            return redactFormURLEncodedBody(body)
        }

        if normalizedContentType.isEmpty ||
            normalizedContentType.contains("json") ||
            normalizedContentType.contains("+json") {
            return redactJSONBody(body) ?? body
        }

        return body
    }

    private func redactJSONBody(_ body: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }

        let redactedObject = redactJSONObject(object)

        guard JSONSerialization.isValidJSONObject(redactedObject) else {
            return nil
        }

        return try? JSONSerialization.data(withJSONObject: redactedObject, options: [.sortedKeys])
    }

    private func redactJSONObject(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { partialResult, item in
                if sensitiveBodyFields.contains(Self.normalize(field: item.key)) {
                    partialResult[item.key] = redactionPlaceholder
                } else {
                    partialResult[item.key] = redactJSONObject(item.value)
                }
            }
        }

        if let array = object as? [Any] {
            return array.map(redactJSONObject(_:))
        }

        return object
    }

    private func redactFormURLEncodedBody(_ body: Data) -> Data {
        guard let bodyString = String(data: body, encoding: .utf8) else {
            return body
        }

        let redactedPairs = bodyString
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair -> String in
                let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let rawKey = components.first.map(String.init) else {
                    return String(pair)
                }

                let decodedKey = rawKey
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? rawKey

                guard sensitiveBodyFields.contains(Self.normalize(field: decodedKey)) else {
                    return String(pair)
                }

                let encodedPlaceholder = redactionPlaceholder.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ) ?? redactionPlaceholder

                return "\(rawKey)=\(encodedPlaceholder)"
            }
            .joined(separator: "&")

        return redactedPairs.data(using: .utf8) ?? body
    }

    private static func normalize(field: String) -> String {
        field
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
