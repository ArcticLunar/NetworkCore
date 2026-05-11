// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct MultipartFormPart {
    public let name: String
    public let data: Data
    public let filename: String?
    public let contentType: String?

    public init(
        name: String,
        data: Data,
        filename: String? = nil,
        contentType: String? = nil
    ) {
        self.name = name
        self.data = data
        self.filename = filename
        self.contentType = contentType
    }
}
