// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 描述请求的数据承载方式，并由 RequestBuilder 转换为 transport 任务。

import Foundation

/// 端点请求任务类型。
public enum RequestTask {
    /// 无 query、无 body 的普通请求。
    case plain
    /// 将参数追加到 URL query。
    case query([URLQueryItem])
    /// 将 Encodable 值编码为 JSON body。
    case jsonBody(any Encodable)
    /// 使用 `application/x-www-form-urlencoded` 编码 body。
    case formURLEncoded([String: String])
    /// 使用 multipart/form-data 上传多个表单 part。
    case multipart([MultipartFormPart])
    /// 直接上传内存数据，并指定 Content-Type。
    case upload(data: Data, contentType: String)
    /// 使用前台下载，并移动到目标文件。
    case download(destination: URL)
    /// 使用后台 URLSession 下载，并可传入业务 transferIdentifier。
    case backgroundDownload(destination: URL, transferIdentifier: String? = nil)
    /// 打开 WebSocket 时携带 query 和子协议声明。
    case webSocket(queryItems: [URLQueryItem], subprotocols: [String])
}
