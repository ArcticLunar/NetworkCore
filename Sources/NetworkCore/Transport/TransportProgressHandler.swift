// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 封装上传和下载进度回调。

import Foundation

/// transport 进度回调集合。
public struct TransportProgressHandler {
    public typealias Callback = (Progress) -> Void

    /// 上传进度回调。
    public let upload: Callback?
    /// 下载进度回调。
    public let download: Callback?

    public init(
        upload: Callback? = nil,
        download: Callback? = nil
    ) {
        self.upload = upload
        self.download = download
    }
}
