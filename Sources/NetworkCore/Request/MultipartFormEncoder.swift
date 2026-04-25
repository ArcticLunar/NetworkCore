import Foundation

enum MultipartFormEncoder {
    static let boundary = "Boundary-\(UUID().uuidString)"

    static func encode(parts: [MultipartFormPart]) throws -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for part in parts {
            body.append(boundaryPrefix.data(using: .utf8) ?? Data())

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append("\(disposition)\r\n".data(using: .utf8) ?? Data())

            if let contentType = part.contentType {
                body.append("Content-Type: \(contentType)\r\n".data(using: .utf8) ?? Data())
            }

            body.append("\r\n".data(using: .utf8) ?? Data())
            body.append(part.data)
            body.append("\r\n".data(using: .utf8) ?? Data())
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8) ?? Data())
        return body
    }
}
