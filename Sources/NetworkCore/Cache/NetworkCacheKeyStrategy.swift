// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义缓存 key 的 URL 归一化策略。

import Foundation

/// 生成缓存 key 时使用的请求归一化方式。
public enum NetworkCacheKeyStrategy: Equatable, Sendable {
    /// 完全使用原始请求作为缓存 key。
    case request
    /// 对 query item 排序并移除 fragment，减少等价 URL 的缓存重复。
    case normalizeQueryItems
}
