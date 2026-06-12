// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 表示 transport 层需要执行的具体任务类型。

import Foundation

/// transport 对 `URLRequest` 的执行方式。
public enum TransportTask: Sendable {
    /// 普通数据请求。
    case request
    /// 上传内存数据。
    case upload(data: Data)
    /// 前台下载到目标文件。
    case download(destination: URL)
    /// 后台下载到目标文件。
    case backgroundDownload(destination: URL, transferIdentifier: String?)
}

/// 已经完成 URL、header、body 和任务类型构建的请求。
public struct TransportRequest: Sendable {
    /// 底层 URLSession / Alamofire 可执行的请求。
    public let urlRequest: URLRequest
    /// 请求执行方式。
    public let task: TransportTask

    public init(urlRequest: URLRequest, task: TransportTask) {
        self.urlRequest = urlRequest
        self.task = task
    }
}
