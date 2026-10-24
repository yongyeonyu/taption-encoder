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
./scripts/verify.sh           # 构建 + 全量测试（CI 跑的是同一个脚本）
./scripts/verify.sh --build   # 只构建，快很多
```

**启用推送前自动验证（每个 clone 做一次）：**

```bash
git config core.hooksPath .githooks
```

之后 `git push` 会先跑构建和测试，失败就拒绝推送。纯文档改动会自动跳过。
紧急情况：`SKIP_VERIFY=1 git push`，并在 PR 里说明原因。

### 模拟器是按名字占有的，不是共享的

CI runner 和开发机是同一台 Mac，所以 `verify.sh` 不再复用「开着的任意设备」，而是各自持有：

| 调用方 | 设备名 |
|---|---|
| CI | `verify-ci` |
| 本地 / 钩子 | `verify-local` |
| 第三个并发 | `TAPTION_SIMULATOR_NAME=verify-2 ./scripts/verify.sh` |

同名占用会直接报错并打印持有者 pid，而不是让两边互相杀掉对方的测试宿主。每次运行还会先
`simctl erase`，消掉一类「只在全量运行时失败」的假红。

**并发是安全的，但不是免费的**：全套是视频编码瓶颈，CI 单独约 170 秒，CI + 本地并发约 1200 秒。
默认请串行。

### 被退役的证明测试

有 34 个测试需要 57 个真实世界样本视频，这些样本为保持仓库「只含源码」被有意移除，对应测试按
名字排除。要跑它们：

```bash
./scripts/restore-retired-samples.sh          # 从 git 历史恢复真实样本
./scripts/verify.sh                           # 默认套件 + 退役证明
./scripts/restore-retired-samples.sh --clean  # 撤销
```

样本是**从历史恢复**而不是生成的：这些测试要证明 App 能读它自己没写出来的格式，合成文件不构成
证据。详见 [docs/code-review §5.7](docs/code-review/README.md)。

<details>
<summary>为什么需要这一层</summary>

GitHub 托管的 `macos-26` 镜像只带 Xcode 26.6，而本项目需要 iOS 27 SDK。CI 因此跑在
维护者 Mac 上的 self-hosted runner（`~/actions-runner`），也就是说**CI 只在 Mac 开机、
runner 在线时才工作**，掉线时 job 会一直排队而不是变红。

本地钩子让「推上去之前就知道结果」，不依赖那台机器是否在线。CI 和钩子调同一个
`scripts/verify.sh`，所以两边不会出现不同的判定标准。

安全前提（public 仓库）见 [README §6](docs/code-review/README.md)。

</details>

### 底层命令

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
