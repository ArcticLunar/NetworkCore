# NetworkCore Migration

这份文档描述的是从“应用内手工拼装网络栈”迁移到 `NetworkCore V1` 统一装配的建议路径。

## 迁移目标

迁移的目标是把职责稳定分层：

- `NetworkCore` 负责通用协议、默认策略和运行时能力
- 应用层负责凭证存储、token refresh、生命周期桥接、业务 observer、业务下载入口
- 装配入口统一收口到 `NetworkDefaults`

## 推荐迁移顺序

### 1. 先统一环境与 client 创建

旧方式：

```swift
let configuration = NetworkConfiguration(
    environment: environment,
    observers: [NetworkLogger()]
)
let session = NetworkDefaults.makeSession(baseURL: environment.baseURL)
let client = NetworkClient(
    configuration: configuration,
    transport: AlamofireTransport(session: session)
)
```

推荐方式：

```swift
let configuration = NetworkDefaults.makeProductionConfiguration(
    environment: environment
)

let client = NetworkDefaults.makeProductionClient(
    configuration: configuration
)
```

### 2. 把应用专有鉴权实现留在应用层

应用层应当拥有：

- `AuthCredentialsStore` 的具体实现
- `TokenRefresher` 的具体实现
- `UnauthorizedHandler` 的具体实现
- 最终 factory

框架只负责：

- `AuthInterceptor`
- `AuthRefreshCoordinator`
- `UnauthorizedPolicy`

### 3. 生命周期桥接通过 `NetworkAppLifecycleMonitor` 注入

如果 streaming reconnect 需要感知 app active / inactive：

- 应用层实现 `NetworkAppLifecycleMonitor`
- 通过 `NetworkConfiguration.appLifecycleMonitor` 注入

### 4. Reachability 统一走 monitor 注入

如果应用需要基于真实网络路径做 gating：

- 使用 `SystemNetworkReachabilityMonitor`
- 通过 `makeProductionConfiguration(... reachabilityMonitor: ...)` 注入

endpoint 级差异通过 `RequestOptions.reachabilityRequirement` 声明。

### 5. 背景下载接入统一 manager

推荐方式：

1. 创建单例 `BackgroundDownloadManager`
2. 使用 `NetworkDefaults.defaultBackgroundDownloadSessionIdentifier()` 生成 session id
3. 通过 `NetworkDefaults.makeProductionClient(... backgroundDownloadManager: manager)` 注入
4. 在应用 delegate 中把系统 completion handler 转给 `BackgroundTransferSystemCoordinator.shared`

### 6. 迁移 endpoint 级配置

把散落在调用方的差异迁回 endpoint 的 `RequestOptions`。

优先迁移这些项：

- `isIdempotent`
- `allowsLogging`
- `metricsPath`
- `networkCachePolicy`
- `cacheTimeToLive`
- `cacheKeyStrategy`
- `unauthorizedStrategy`
- `reachabilityRequirement`
- `maximumUploadSizeOnExpensiveNetwork`
- `maximumUploadSizeOnConstrainedNetwork`
- `streamReconnectPolicy`

### 6.1 Safe decoding 迁移口径

`V1` 已提供 safe decoding，但默认仍是严格模式。

迁移原则：

- 默认保持 `NetworkConfiguration.defaultDecodingPolicy == .strict`
- 只有明确允许字段级降级的 endpoint，才显式设置 `decodingPolicy = .safe`
- DTO 同时使用 `Defaulted` / `LossyArray` / `LossyDictionary` / `StringBackedInt` / `StringBackedBool` 等 wrappers，safe mode 才会真正生效

### 7. 保留 direct `NetworkConfiguration(...)` 的适用场景

只有下面几类场景建议直接初始化：

- 需要完全替换默认 observers
- 需要完全替换默认 response validators
- 需要测试桩装配
- 需要非 production 的特殊集成

## 应用层最终应保留什么

- 环境定义
- token store / refresh 实现
- unauthorized 行为实现
- lifecycle monitor
- metrics sink / log sink
- background download 页面与 store
- 业务 endpoint

## 验收标准

迁移到 `V1` 后，至少应满足：

- 请求 client 创建路径统一
- auth 装配只保留一份 factory
- background download manager 只保留一份主实例
- endpoint 级缓存 / 网络策略改由 `RequestOptions` 驱动
- 应用 delegate 已正确转发 background session completion handler
- package 自身测试通过
