<!--
Copyright (c) 2026 ArcticLunar
All rights reserved.
-->

# Publishing NetworkCore

`NetworkCore` 同时支持 Swift Package Manager 和 CocoaPods。

## 仓库准备

建议使用独立仓库：

- 仓库名：`NetworkCore`
- 默认分支：`main`
- 发布路径：仓库根目录即当前 `Packages/NetworkCore`

需要提交的核心文件：

- `Package.swift`
- `NetworkCore.podspec`
- `Sources/`
- `Tests/`
- `README.md`
- `Migration.md`
- `V1.md`
- `LICENSE`

## Swift Package Manager

接入方式：

```swift
.package(url: "https://github.com/ArcticLunar/NetworkCore.git", from: "1.0.0")
```

## CocoaPods

接入方式：

```ruby
pod 'NetworkCore', '~> 1.0'
```

本地校验：

```bash
pod lib lint NetworkCore.podspec --allow-warnings
```

## 发布步骤

1. 在独立仓库提交发布内容并推送到 `main`
2. 打 tag，例如 `1.0.0`
3. 推送 tag：

```bash
git tag 1.0.0
git push origin main --tags
```

4. 发布 CocoaPods：

```bash
pod trunk push NetworkCore.podspec --allow-warnings
```

## 从 Bolt 仓库拆分

如果当前代码仍位于 `Bolt` 仓库内，可以用 subtree 保留历史：

```bash
git subtree split --prefix=Packages/NetworkCore -b codex/networkcore-release
git clone git@github.com:ArcticLunar/NetworkCore.git /tmp/NetworkCore
git -C /tmp/NetworkCore checkout -b main
git -C /tmp/NetworkCore pull --allow-unrelated-histories /Users/time/Desktop/Bolt codex/networkcore-release
```

或者直接把 `Packages/NetworkCore` 初始化成独立仓库后推送。
