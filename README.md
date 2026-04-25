# NetworkCore

<p align="center">
  <img src="./Assets/banner.png" alt="NetworkCore" width="720">
</p>
<div align="center">
  <p>
    <strong>A production-grade networking framework for Apple platforms.</strong>
  </p>

  <p>
    <a href="https://github.com/ArcticLunar/NetworkCore/stargazers"><img src="https://img.shields.io/github/stars/ArcticLunar/NetworkCore" alt="Stars Badge"/></a>
    <a href="https://github.com/ArcticLunar/NetworkCore/network/members"><img src="https://img.shields.io/github/forks/ArcticLunar/NetworkCore" alt="Forks Badge"/></a>
    <a href="https://github.com/ArcticLunar/NetworkCore/pulls"><img src="https://img.shields.io/github/issues-pr/ArcticLunar/NetworkCore" alt="Pull Requests Badge"/></a>
    <a href="https://github.com/ArcticLunar/NetworkCore/issues"><img src="https://img.shields.io/github/issues/ArcticLunar/NetworkCore" alt="Issues Badge"/></a>
    <a href="https://github.com/ArcticLunar/NetworkCore/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/ArcticLunar/NetworkCore?color=2b9348"></a>
    <a href="https://github.com/ArcticLunar/NetworkCore/blob/main/LICENSE"><img src="https://img.shields.io/github/license/ArcticLunar/NetworkCore?color=2b9348" alt="License Badge"/></a>
  </p>
</div>

## 🌟 Overview

`NetworkCore` is a production-grade networking framework for Apple platforms. It is designed to solve the recurring problem of rebuilding request pipelines, auth flows, observability, retry, cache, reachability, streaming, and background transfer infrastructure in every app by providing a unified, extensible, release-ready networking foundation.

## ✨ Features

- 🚀 **Production-ready presets** - Standardized assembly through `NetworkDefaults`
- 🛡️ **Security-aware** - Default trust policy, certificate pinning, public key pinning, and redacted logging
- 🔧 **Extensible** - Observer, metrics, auth, cache, reachability, retry, and validator extension points
- 📡 **Streaming support** - Built-in SSE and WebSocket support with reconnect control
- 🌐 **Resilience focused** - Retry, circuit breaker, endpoint failure tracking, and reachability gating
- 📦 **Distribution ready** - Supports both Swift Package Manager and CocoaPods

## 🎯 Quick Start

### Prerequisites

- Xcode 15.4 or later
- Swift 5.10
- iOS 17.0+ or macOS 13.0+

### Installation

#### Swift Package Manager

```swift
.package(url: "https://github.com/ArcticLunar/NetworkCore.git", from: "1.0.0")
```

#### CocoaPods

```ruby
pod 'NetworkCore', '~> 1.0'
```

### Create a production configuration

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

### Define an endpoint

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

### Send a request

```swift
let user = try await client.request(
    UserEndpoint(id: "42")
)
```

## 📚 Documentation

- [Migration Guide](./Migration.md)
- [V1 Capability Notes](./V1.md)
- [Publishing Guide](./Publishing.md)
- [Release 1.0.0 Notes](./Release-v1.0.0.md)

## 🏗️ Project Structure

```text
NetworkCore/
├── Sources/NetworkCore/
│   ├── Auth/
│   ├── BackgroundTransfer/
│   ├── Cache/
│   ├── Client/
│   ├── Configuration/
│   ├── Endpoint/
│   ├── Error/
│   ├── Observability/
│   ├── Pipeline/
│   ├── Reachability/
│   ├── Request/
│   ├── Resilience/
│   ├── Response/
│   ├── Streaming/
│   ├── Support/
│   └── Transport/
├── Tests/NetworkCoreTests/
├── Package.swift
├── NetworkCore.podspec
├── README.md
└── LICENSE
```

## 🤝 Integration Principles

- 应用专有实现通过协议注入，不放回框架内部
- endpoint 级差异通过 `RequestOptions` 声明
- 常规接入优先走 `NetworkDefaults` production preset
- 后台下载 session identifier 统一通过 `NetworkDefaults.defaultBackgroundDownloadSessionIdentifier(...)` 生成

## 📊 Current Scope

- [x] Standard HTTP request pipeline
- [x] SSE and WebSocket streaming
- [x] Cache with TTL and conditional revalidation
- [x] Auth refresh and unauthorized handling extension points
- [x] Observability profiles and redaction
- [x] Reachability-aware policies
- [x] Circuit breaker and endpoint failure tracking
- [x] Background download support

## 📄 License

This project is distributed under the license defined in the [LICENSE](./LICENSE) file.

## 📞 Support

- 🐛 Issues: [GitHub Issues](https://github.com/ArcticLunar/NetworkCore/issues)
- 🔀 Pull Requests: [GitHub Pull Requests](https://github.com/ArcticLunar/NetworkCore/pulls)

---

<div align="center">
  Maintained by <a href="https://github.com/ArcticLunar">@ArcticLunar</a>
</div>
