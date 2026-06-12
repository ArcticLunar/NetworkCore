# NetworkCore 仓库说明

## 注释规则

- 新增或修改代码时必须同步补充注释，优先说明职责、业务意图、边界条件和风险。
- 所有新增注释必须使用中文，包含 `///` 文档注释和 `//` 行内说明。
- `token`、`unauthorized`、`store`、`Keychain`、`Bearer`、HTTP 字段名、类型名、方法名和协议名等工程术语可以保留英文，不需要强行翻译。
- 对外公开的类型、属性、方法、初始化器和协议要求优先使用 `///` 文档注释。
- 私有复杂逻辑使用 `//` 注释解释“为什么这么做”，尤其是鉴权刷新、重试、缓存、后台下载、流式连接、可观测性和错误映射。
- 修改已有逻辑时必须同步更新过期注释，不能让注释描述旧行为或旧约束。
- 注释要简洁准确，避免写重复代码表面的说明。

<claude-mem-context>
# Memory Context

# [NetworkCore] recent context, 2026-05-11 6:14pm GMT+8

No previous sessions found.
</claude-mem-context>
