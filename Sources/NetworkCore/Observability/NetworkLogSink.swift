// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol NetworkLogSink {
    func log(_ record: NetworkLogRecord)
}
