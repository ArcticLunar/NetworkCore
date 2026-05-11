// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct ContentTypeValidator: ResponseValidator {
    public init() {}

    public func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws {
        guard response.downloadedFileURL == nil else {
            return
        }

        guard context.expectsEmptyResponseBody == false else {
            return
        }

        guard response.data.isEmpty == false else {
            return
        }

        let acceptableContentTypes = context.acceptableContentTypes.map(normalizeContentType(_:))
        guard acceptableContentTypes.isEmpty == false else {
            return
        }

        let responseContentType = response.response.value(forHTTPHeaderField: "Content-Type")
        let normalizedContentType = responseContentType.map(normalizeContentType(_:))

        guard let normalizedContentType else {
            throw NetworkError.unacceptableContentType(nil)
        }

        let matches = acceptableContentTypes.contains { acceptableContentType in
            normalizedContentType == acceptableContentType
        }

        guard matches else {
            throw NetworkError.unacceptableContentType(responseContentType)
        }
    }

    private func normalizeContentType(_ contentType: String) -> String {
        contentType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? contentType.lowercased()
    }
}
