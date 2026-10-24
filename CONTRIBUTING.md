# 贡献指南

## 开工前

1. 读 [`docs/code-review/README.md`](docs/code-review/README.md)——标准、风险分级、流程都在那里。
2. 按风险级别判断这次改动要几道闸（T1 核心 / T2 功能 / T3 低风险）。

## 三条硬规则

- **不直接推 `main`。** 一切改动走分支 + PR。（已由分支保护强制，管理员也不例外——见 README §6）
- **PR ≤ 400 行。** 超了就拆；拆不动的，在描述里说明为什么。
- **CI 必须绿。** 构建通过、478 个测试全过、无新增警告。

## 开 PR

模板会自动带出（`.github/pull_request_template.md`）。填完风险级别与验证项，
T1 改动必须附真机验证记录。

## 审查

单人维护，所以"审查"= 隔夜复审自己的 diff：PR 开好后至少隔一天再读，按
[`docs/code-review/checklist.md`](docs/code-review/checklist.md) 走一遍，把发现写成评论再改。
配合 AI 复审补漏。这条不是可选项，是 T1 / T2 的合并条件。

## 本地构建与测试

```bash
xcodebuild test \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
```

`-disable-sandbox` 是必需的：本机环境下 `swift-plugin-server` 被沙箱拦住会导致
宏（Observation）编译失败。`-parallel-testing-enabled NO` 也是必需的，并行 clone
会让整套测试偶发卡死。
