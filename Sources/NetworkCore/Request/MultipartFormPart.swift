// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 描述 multipart/form-data 中的单个表单 part。

import Foundation

/// 一个 multipart 表单字段或文件字段。
public struct MultipartFormPart {
    /// 表单字段名。
    public let name: String
    /// 字段内容数据。
    public let data: Data
    /// 文件名；为空时按普通字段处理。
    public let filename: String?
    /// part 级 Content-Type。
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
