// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 校验非空普通响应的 Content-Type 是否符合端点契约。

import Foundation

/// Content-Type validator，默认用于阻止 HTML、纯文本等非预期响应进入 JSON 解码。
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

        // 下载和空响应没有 JSON body 契约，因此只对有 body 的普通响应校验 Content-Type。
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
