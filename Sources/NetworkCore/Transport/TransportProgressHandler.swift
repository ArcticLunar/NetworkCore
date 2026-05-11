// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct TransportProgressHandler {
    public typealias Callback = (Progress) -> Void

    public let upload: Callback?
    public let download: Callback?

    public init(
        upload: Callback? = nil,
        download: Callback? = nil
    ) {
        self.upload = upload
        self.download = download
    }
}
