# NetworkCore

`NetworkCore` 是一个独立的生产级网络框架，提供请求、流式、缓存、鉴权扩展点、观测、网络策略、熔断和后台下载能力。

支持分发方式：

- Swift Package Manager
- CocoaPods

当前推荐优先使用三个统一入口：

- `NetworkDefaults.makeProductionConfiguration(...)`
- `NetworkDefaults.makeProductionClient(...)`
- `NetworkDefaults.defaultBackgroundDownloadSessionIdentifier(...)`

## 能力边界

`NetworkCore` 当前包含：

- 普通请求：`request(...)` / `requestData(...)`
- 流式请求：SSE / WebSocket / `openStream(...)`
- 生产默认装配：重试、响应校验、缓存存储、observability profile、安全策略
- 鉴权扩展点：`AuthCredentialsStore` / `TokenRefresher`
- 观测扩展点：`NetworkObserver` / `NetworkMetricsSink` / `NetworkLogSink`
- 缓存扩展点：`NetworkCacheStore`
- 网络状态扩展点：`NetworkReachabilityMonitor`
- 韧性能力：`CircuitBreaker` / `EndpointFailureTracker`
- 后台下载：`BackgroundDownloadManager`

## 快速开始

```swift
import NetworkCore

let environment = NetworkEnvironment(
    name: "prod",
    baseURL: URL(string: "https://api.example.com")!
)

let configuration = NetworkDefaults.makeProductionConfiguration(
    environment: environment
)

let client = NetworkDefaults.makeProductionClient(
    configuration: configuration
)
```

定义 endpoint：

```swift
struct UserEndpoint: APIEndpoint {
    typealias Response = User

    let path: String
    let method: HTTPMethod = .get
    let task: RequestTask = .plain

    init(id: String) {
        self.path = "users/\(id)"
    }
}
```

发起请求：

```swift
let user = try await client.request(
    UserEndpoint(id: "42")
)
```

## 安装

### Swift Package Manager

```swift
.package(url: "https://github.com/ArcticLunar/NetworkCore.git", from: "1.0.0")
```

### CocoaPods

```ruby
pod 'NetworkCore', '~> 1.0'
```

## 接入原则

- 应用专有实现通过协议注入，不放回框架内部
- endpoint 级差异通过 `RequestOptions` 声明
- 常规接入优先走 `NetworkDefaults` production preset
- 后台下载 session identifier 统一通过 `NetworkDefaults.defaultBackgroundDownloadSessionIdentifier(...)` 生成

## 文档

- [Migration.md](./Migration.md)
- [V1.md](./V1.md)
- [Publishing.md](./Publishing.md)
