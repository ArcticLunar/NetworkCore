import Foundation

public enum RequestTask {
    case plain
    case query([URLQueryItem])
    case jsonBody(any Encodable)
    case formURLEncoded([String: String])
    case multipart([MultipartFormPart])
    case upload(data: Data, contentType: String)
    case download(destination: URL)
    case backgroundDownload(destination: URL, transferIdentifier: String? = nil)
    case webSocket(queryItems: [URLQueryItem], subprotocols: [String])
}
