<!--
Copyright (c) 2026 ArcticLunar
All rights reserved.
-->

# NetworkCore 1.0.0

`NetworkCore 1.0.0` 是首个对外发布版本，目标是提供一套可直接用于生产环境的 iOS/macOS 网络框架基础设施。

本版本已经完成从业务工程内嵌实现到独立库形态的切分，并同时支持：

- Swift Package Manager
- CocoaPods

## Highlights

- 统一生产装配入口：`NetworkDefaults.makeProductionConfiguration(...)`
- 统一生产 client 入口：`NetworkDefaults.makeProductionClient(...)`
- 支持普通请求、SSE、WebSocket、后台下载
- 内建缓存能力：TTL、cache key normalization、条件请求
- 内建韧性能力：retry、reachability gate、circuit breaker
- 内建可观测性：logger、metrics observer、redaction、release/debug profile
- 内建安全策略：默认 server trust policy、pinned certificates、public key pinning
- 支持 safe decoding、业务校验、错误映射和 unauthorized/refresh 流程扩展

## Included Capabilities

### Requesting

- `request(...)`
- `requestData(...)`
- `APIEndpoint`
- `RequestTask`
- `RequestOptions`

### Streaming

- Server-Sent Events
- WebSocket
- reconnect controller
- `Last-Event-ID`
- send / ping / close

### Cache

- protocol cache policy
- stale-while-revalidate
- TTL
- cache key normalization
- conditional revalidation

### Auth

- `AuthCredentialsStore`
- `TokenRefresher`
- unauthorized handling extension points

### Observability

- `NetworkObserver`
- `NetworkLogger`
- `NetworkMetricsObserver`
- `NetworkLogSink`
- `NetworkMetricsSink`
- release-safe redaction strategy

### Resilience

- retry policy
- reachability-aware request gating
- endpoint-level network policy
- expensive/constrained network upload limits
- `CircuitBreaker`
- `EndpointFailureTracker`

### Background Transfer

- `BackgroundDownloadManager`
- resume/pause/restore
- progress/status lifecycle

## Distribution

### Swift Package Manager

```swift
.package(url: "https://github.com/ArcticLunar/NetworkCore.git", from: "1.0.0")
```

### CocoaPods

```ruby
pod 'NetworkCore', '~> 1.0'
```

## Validation

The release was validated with:

- `swift test`
- `pod lib lint NetworkCore.podspec --allow-warnings --quick`

## Notes

- 当前版本聚焦框架能力本身，不包含具体业务 API 实现。
- `README.md`、`Migration.md`、`V1.md` 和 `Publishing.md` 已与原业务工程文档解耦。
