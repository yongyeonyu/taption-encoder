# 代码审查标准与流程

> 仓库：`yongyeonyu/taption-encoder`（iOS / Swift，Taption Encoder 与 BOKKI Encoder）
> 版本：1.0 · 2026-10-24
> 维护：每季度回顾一次；修改本文档本身也要走 PR。

本文档分两部分：**标准**（什么算合格、什么必须拦住）和**流程**（谁来审、什么时候审、怎么合并）。
日常执行用 [`checklist.md`](./checklist.md)，开 PR 时填 `.github/pull_request_template.md`。

---

## 0. 现状：问题不在水平，在闸门

先看实测数据，因为它决定了标准该往哪里用力。

| 指标 | 实测 | 说明 |
| --- | --- | --- |
| 提交数 / 作者数 | 221 / 1 | 全部直接进入 `main` |
| Pull Request | **0** | 没有审查记录，也没有变更说明可查 |
| CI | 无 | 478 个单元测试只在本机跑 |
| 格式 / 静态检查 | 无 | 风格取决于提交当天 |
| 应用代码 | 82 文件 / 46,239 行 | |
| 最大应用文件 | `HomeViewModel.swift` **7,296 行** | 一个类型同时承担导入、队列、编码、广告、持久化 |
| 测试代码 | 4 文件 / 19,905 行，其中 **490 个用例集中在 `CodecRoutePlannerTests.swift`（18,266 行）** | 一个文件装下全部回归 |
| 强制解包 / `TODO` | **0 / 0** | 这两项其实很干净 |
| 隐私清单 | 已补齐（`TaptionEncoder/PrivacyInfo.xcprivacy`） | 2026-10-24 新增：`UserDefaults` → `CA92.1`，未声明追踪 |

结论三条：

1. **质量波动来自没有闸门，不是有人不会写。** 零 PR 意味着任何改动都没有第二双眼睛；`codex/` 分支的存在说明还有 AI 直接产出的代码进来。
2. **两个巨型文件让审查在物理上无法进行。** 一次改动可能只碰 20 行，但审查者无法判断这 20 行与另外 7,200 行的关系。PR 再小，语境是整份文件。
3. **底子是好的。** 0 强制解包、0 遗留 `TODO`、478 个测试——说明纪律存在，缺的是把它固定下来的机制。所以下面的标准**不要**从"加强自律"入手，要从"减少依赖自律"入手。

---

## 1. 五条原则

1. **审查是闸门，不是礼仪。** 没有评论的 `LGTM` 不算审查，视为未审查。
2. **机器管能自动判定的，人管需要判断的。** 格式、编译、测试交给 CI；人只看设计、并发、错误处理、边界。
3. **PR 大小是唯一能自我执行的规则。** 超过 400 行的 PR 不会被认真读，只会被"看起来没问题"地放过。
4. **用级别说话，不用品味。** 每条意见标注 `blocker / major / minor / nit`，作者知道哪些必须改。
5. **审查者对结果负责。** 批准即代表你读懂了这段代码；出问题时审查者和作者一起承担，不是"我只是点了个按钮"。

---

## 2. 风险分级：决定要几道闸

不是所有改动都值得同样的流程。按**出错的后果**分级，而不是按代码量。

| 级别 | 范围 | 合并前必须满足（单人模式） | 典型改动 |
| --- | --- | --- | --- |
| **T1 核心** | `Core/Codecs/**`、`Core/Encoding/**`、`Core/VideoCore/**`、`Core/MediaInspection/**`、`Vendor/**` | ① CI 绿 ② 审查闸门 ③ **真机**验证记录 ④ 有测试或 fixture 证据 | 编码参数、编解码路由、容器封装、文件写入 |
| **T2 功能** | `Features/**`、`Shared/**`、三个扩展 target | ① CI 绿 ② 审查闸门 ③ 模拟器截图或录屏 | 界面、状态机、导入流程、预览 |
| **T3 低风险** | 资源、文案、`Info.plist` 文案、`docs/`、构建脚本 | ① CI 绿 ② 自查清单勾完即可自行合并 | 字符串、图标、文档 |

**单人维护：这就是正式规则，不是过渡方案。** 本仓库目前没有、也不计划有第二位提交者，所以"一位审查者批准"不是延迟执行的条款，而是不适用。T1 / T2 的**审查闸门**由下面三件事组成，缺一不可：

- **24 小时冷却**：PR 开好后不立即合并，隔一天再读一遍自己的 diff。当天读不出的问题（"我以为它是那样"的假设）隔夜往往能读出来。
- **自查清单**：`checklist.md` 逐项过一遍，勾选记录留在 PR 里。
- **AI 复审**：把 diff 连同本清单交给模型跑一遍，只看它指出的 `blocker` 与 `major`，逐条判断是否成立。它能抓漏掉的空值、吞掉的错误、未配对的资源释放，抓不到业务语义——所以它只做补充，不能替代人。

代价要认清：**这三件事提高的是同一双眼睛的命中率，不能替代第二双眼睛。** 没有人会替你发现"你根本没想到的那一类问题"。所以 T1 的额外要求（真机验证、fixture 证据）在单人模式下不是可选项，而是唯一的补偿手段——它们检查的是"结果对不对"，而不是"代码好不好看"。

若将来增加提交者，把上表的"审查闸门"改回"一位审查者批准"，并作为 T1 / T2 的硬性条件。

---

## 3. 流程

```
开草稿 PR → 自动检查 → 转正式 → 审查 → 修改 → 合并 → 事后回归
```

| 阶段 | 触发 | 负责 | 出口条件 | 时限 |
| --- | --- | --- | --- | --- |
| 1. 开草稿 PR | 有第一个可编译的提交 | 作者 | 标题、描述、风险级别、自检清单已填 | — |
| 2. 自动检查 | PR 推送 | CI | 构建通过、478 个测试全过、无新增警告 | ≤ 15 分钟 |
| 3. 转正式 | CI 绿 | 作者 | 点 Ready for review，@ 审查者 | 当日 |
| 4. 审查 | 收到请求 | 审查者 | 清单走完，每条意见带级别 | **24 小时内首轮** |
| 5. 修改 | 收到意见 | 作者 | 每条意见都有回应：改 / 解释 / 反对并说明理由 | 当日 |
| 6. 合并 | 通过 | 作者 | Squash merge，`main` 上一条提交对应一个 PR | — |
| 7. 事后 | T1 变更合并后 | 作者 | 7 天内真机回归一次，结果补在 PR 里 | 7 天 |

**分支与提交约定**（沿用仓库现状，不额外发明）：

- 分支：`feat/`、`fix/`、`refactor/`、`docs/`、`chore/`；AI 产出保留 `codex/` 前缀，便于识别。
- 提交：继续用 `feat:` / `fix:` / `build:` / `docs:` 前缀——现有历史已经在这么做。
- 合并：一律 squash。`main` 不接受直接推送（分支保护见 §6 第 4 周）。

---

## 4. 审查意见的严重级别

| 级别 | 含义 | 作者必须 |
| --- | --- | --- |
| **blocker** | 会崩溃、丢数据、输出损坏、隐私泄漏、并发数据竞争 | 合并前必须改 |
| **major** | 逻辑错误、错误被吞、缺测试、明显性能退化 | 合并前改，或开 issue 并在 PR 里注明 |
| **minor** | 可读性、命名、重复代码 | 本次或下次，作者决定 |
| **nit** | 纯风格偏好 | 可以忽略，**不得作为阻塞理由** |
| **question** | 审查者没看懂 | 必须回答（答完往往暴露出真问题） |
| **praise** | 值得保留的写法 | — |

两条硬规则：

- **`nit` 不能成为唯一的阻塞理由。** 一个 PR 只有 nit 时，直接批准。
- **`blocker` 必须给出复现路径或行号。** 说不出"什么输入会触发"的，降级为 `question`。

---

## 5. 什么必须拦住（本仓库专属）

按"这个项目真的会踩"的顺序排列，不是通用清单。

### 5.1 并发

- `@unchecked Sendable` 是不是只为让编译器闭嘴？理由写了吗？没有理由的一律 blocker。
- `Task` 有取消路径吗？`onDisappear` 之后还在跑的任务，会不会写已经失效的状态？
- 跨线程传递的对象真的线程安全吗？`CVPixelBuffer` 是引用计数安全的，**`AVAssetWriter`、`VLCMediaPlayer` 不是**。
- `@MainActor` 类型里的 `Task { }` 有没有意外跳去后台？
- 共享可变状态有保护吗（actor / lock / main actor）？

### 5.2 编码与解码（T1）

- 每个 `AVAssetWriter` 路径在 `throw` 之后，是否 `cancelWriting()` 并删除半成品文件？
- `finishWriting` 失败时，输出会不会被误报为成功？
- FFmpeg 子进程：退出码检查了吗？**stderr 被读走了吗**（不读会因管道写满而死锁）？超时能杀掉吗？
- 硬件编码器不可用时的回退路径，有测试覆盖吗？
- 非标准分辨率到 FHD/HD/4K 的钳制，有测试吗？——这是真实发生过的缺陷。
- 转码后元数据（旋转、HDR、色彩空间、alpha 通道）还对吗？

### 5.3 文件访问

- `startAccessingSecurityScopedResource()` 与 `stopAccessing...` 是否配对（用 `defer`）？
- 失败路径上的临时文件清理了吗？会不会随使用无限增长？
- 同名文件的覆盖策略明确吗（覆盖 / 重命名 / 拒绝）？

### 5.4 错误处理

- `try?` 吞掉的错误，会不会导致静默失败？编码和文件写入路径上尤其致命。
- 用户看到的失败，有没有可执行的下一步（而不是"出错了"）？
- 日志走 `AppLogger`，不用 `print`。**目前仍有 16 处 `print(` 待清理**，新增的一律 blocker。

### 5.5 权限与隐私

- 新增 `Info.plist` 权限 key，是否同时有用途说明文案？
- 新增第三方 SDK，是否更新隐私清单与 App Store 隐私问卷？
- **`PrivacyInfo.xcprivacy` 已存在**（`TaptionEncoder/PrivacyInfo.xcprivacy`）。新增 required-reason API 时必须在同一个 PR 里补上对应类别与理由——这是清单里唯一"不加就会在提交时被拒"的条目。
- 任何把用户视频内容外发的行为，一律 blocker——本产品的承诺是本地处理。
- 注意区分两处声明：**清单**声明 App 自身访问的 API，**App Store Connect 问卷**声明数据收集。广告数据由 Google Mobile Ads 自带的清单声明，但问卷里仍需勾选，两者不能互相替代。

### 5.6 扩展 target

- Live Activity / Thumbnail 扩展与主 App 共享的模型，两边都能编译吗？改了共享模型必须同时构建全部 target（本项目共 14 个 target）。

### 5.7 测试

- 新逻辑有测试吗？修 bug 是先写能复现的测试吗？
- **新增测试文件必须手工注册到 `project.pbxproj`**，忘了会静默不执行。这一条本身是 blocker 级陷阱——它让"测试通过"变成假信号。

#### 被退役的证明测试（retired proofs）

有 34 个测试需要 57 个真实世界样本（`TaptionEncoder/TestVideos`），commit `02e3ad4`
把那个目录从仓库里拿掉了（61 个文件 / 42 MB），所以它们被列进
`retiredSourceOnlyProofTestNames`，默认不执行。

要跑它们，用仓库里的脚本，**不要用 FFmpeg 生成样本**：

```bash
./scripts/restore-retired-samples.sh          # 从 git 历史恢复真实样本 + 打开开关
./scripts/verify.sh                           # 默认套件 + 退役证明
./scripts/restore-retired-samples.sh --clean  # 撤销
```

为什么不能生成：这些测试的目的是证明 App 能读**它自己没写出来的**格式（Cinepak、Sorenson
Video 1、RealVideo、RoQ、ASUS V1）。用本机 FFmpeg 造出来的文件证明不了这一点，而且
`testBundledSampleSourceNoticeRejectsGeneratedOnlyFixtures` 就是专门拦这种做法的。

⚠️ 开关是 `/tmp` 下的**机器级**文件，不是仓库级的。开着它跑 CI 会让 CI 也去跑那 34 个测试。
用完记得 `--clean`。

---

## 6. 自动化：机器先过一遍

### 必须绿（否则不允许合并）

1. `xcodebuild build` 无**新增**警告。
2. 单元测试全过（当前 478 个，4 个 skip 属预期）。
3. 无新增 `print(`、无新增 `try!` / `as!` / 强制解包。

### 为什么必须自托管（2026-10-24 实测）

第一次真实运行就暴露了：GitHub 托管的 `macos-26` 镜像**只带 Xcode 26.6 / iOS 26.x SDK**，而本项目
需要 iOS 27 SDK（`AVAudioSession.activate(options:completionHandler:)` 这类 API 在 26 的 SDK 里标记
为 iOS 不可用，编译直接报错）。托管 runner 连编译都过不去，所以 CI 从 2026-10-24 起跑在**维护者这台
Mac** 上（`runs-on: [self-hosted, macOS, bokki]`），runner 目录在仓库之外（`~/actions-runner`）。

**这意味着 CI 只在 Mac 开机、runner 在线时才工作。** 掉线时 job 会一直排队——不会变红，也不会
变绿。分支保护**没有**把本 workflow 设为必需检查，正是为了让排队不阻塞合并。

### self-hosted runner 的安全前提（public 仓库，必读）

runner 会执行 workflow 里写的任何东西；对 `pull_request` 事件，workflow 文件取自 PR 本身。
也就是说 **fork 的 PR 可以改 workflow，然后在这台 Mac 上执行任意命令**——token、Keychain、
Xcode 里的 Apple ID 全在里面。三道防线：

| 防线 | 做法 | 作用 |
| --- | --- | --- |
| 1. job 级 `if` | `github.event.pull_request.head.repo.full_name == github.repository` | fork PR 在分配 runner **之前**被跳过 |
| 2. 仓库设置 | 「Require approval for all outside collaborators」 | fork PR 的 workflow 根本不启动，除非人工点批准 |
| 3. 分支保护 | 不把本 workflow 设为必需检查 | runner 掉线时排队不卡死合并 |

**不要拆掉任何一道。** 第 2 道是真正拦得住的那一道——第 1 道写在 workflow 里，而 fork PR 恰好
可以改 workflow。

如果你不想承担这个风险，把 `runs-on` 改回 `macos-26` 并删掉 job 级 `if`，CI 会退化成「跳过构建」，
本地闸门继续作为唯一的验证手段。

### 本地闸门（保留）

仓库自带 `scripts/verify.sh`（构建 + 全量测试，用本机 Xcode 27）和 `.githooks/pre-push`
（测试不通过就拒绝推送）。每个 clone 启用一次：

```bash
git config core.hooksPath .githooks
```

紧急情况用 `SKIP_VERIFY=1 git push` 绕过，并在 PR 里写明原因。

CI 和钩子**调同一个脚本**，这是故意的：「验证通过」只能有一个定义，否则迟早出现本地绿、CI 红，
然后没人再相信任何一边。

### 一台机器、两个使用者：模拟器必须分开（2026-10-24 实测）

runner 和开发机是同一台 Mac，而 `verify.sh` 原来是这样挑设备的：

```bash
UDID=$(xcrun simctl list devices booted | grep -oE '<uuid>' | head -1)
```

也就是「谁开着就用谁」。于是 CI 和本地各跑一次，就落到同一台模拟器上，后启动的 `xcodebuild test`
把先启动的测试宿主 SIGKILL 掉。表现出来**完全像代码坏了**：

| 现象 | 实际原因 |
| --- | --- |
| 473 passed / 3 failed，三条都是 `Test crashed with signal kill` | 测试宿主被杀 |
| 三条都是最重的 VC-1 编码（`testBundledFFmpegDecodeBridge…` 等） | 跑得最久，撞上另一次启动的概率最高 |
| 附带 `Failure collecting diagnostics from simulator: Timed out after 600.0 seconds` | 设备已被另一个 xcodebuild 占用 |
| 单独跑或重跑就绿 | 没有竞争者了 |

结论：**这不是偶发，是结构问题。** 重跑只是把碰撞概率降到零，没有修掉任何东西。

现在的做法是不共享——每个使用者一台自己的模拟器，不再看「谁开着」：

| 使用者 | 设备名 | 说明 |
| --- | --- | --- |
| CI | `verify-ci` | `CI=true` 时自动选择 |
| 本地 / 钩子 | `verify-local` | 默认 |
| 第三个并发 | 自己起名 | `TAPTION_SIMULATOR_NAME=verify-2 ./scripts/verify.sh` |

同一台设备被两个进程抢时会立刻报错退出，而不是悄悄互相踩：

```
error: the 'verify-local' simulator is already in use (lock: /tmp/taption-verify-verify-local.lock).
```

另外每次运行都会 `simctl erase` 这台设备。跨次复用会留下上一次的 app 容器，残留的 `UserDefaults`
会让少数测试**只在全量运行时**失败（典型是 `testAutoSizeShowsEstimatedOutputInMainTileAndPopoverValue`，
单跑就过）。擦除只要几秒，直接消掉这一整类假红。

#### 隔离是「安全」了，不是「免费」了（实测）

| 场景 | 耗时 |
| --- | --- |
| CI 单独 | 169 s |
| CI + 本地并发 | **1174 s**（约 7 倍） |

视频编码测试吃满核心，并发时双方互相拖慢。不会像以前那样把对方杀死，但也不会快。
**默认原则仍然是串行**——本地闸门等 CI 结束再跑。并发只在赶时间时用。

### runner 会继承桌面 shell 的环境（2026-10-24 实测）

修完模拟器之后 CI 又红了一次，而这次连测试都没开始：**18 秒**失败，唯一失败的 step 是
`actions/checkout@v4`，`Check toolchain` 和 `Build and test` 全是 `skipped`。

```
Error: File was unable to be removed
  Error: [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":50,"threshold":50,...}
```

runner 是一台普通桌面 Mac，会继承**启动它的那个 shell** 的环境。这份环境里带着 agent 沙箱的
shell 包装器：`NODE_OPTIONS=--require=.../node-language-shim.cjs`、`BASH_ENV=.../shell-runtime-bash-env.sh`、
`CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD=50`，以及排在 `/usr/bin` 前面的 `shim/` 目录。

`actions/checkout` 是 node 写的，第一件事是删掉上一次的检出目录（远超 50 个文件）→ 包装器拒绝
→ checkout 死在任何代码跑起来之前。

**修法在仓库这一侧**，job 级 `env` 对所有 step 生效（包括 `uses:` 的 action）：

```yaml
env:
  NODE_OPTIONS: ""
  BASH_ENV: /dev/null
  PATH: /usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

`BASH_ENV` 必须指向 `/dev/null` 而不是空串——bash 只检查变量是否存在，空值会让它去 source 一个
名字都没有的文件。

机器侧的 `~/actions-runner/.path` 也顺手清了（原文件备份为 `.path.bak-with-workbuddy-shims`），但**不够**：
runner 在启动时就把 `.path` 和进程环境缓存下来了，而它不是一个 launchd 服务，job 内部没法重载。

### 两种「CI 红、本地绿」怎么区分

| | 失败位置 | 日志特征 |
| --- | --- | --- |
| 模拟器争用 | 测试执行中 | `Test crashed with signal kill`、600 s diagnostics 超时、`verify.log` 有内容 |
| shell 环境泄漏 | 代码启动前 | 唯一失败的 step 是 checkout、后续全 `skipped`、`verify.log` **0 字节** |

**`verify.log` 是 0 字节，就一定不是代码问题。**

### `cancel-in-progress` 和同一个 work 目录

`concurrency.cancel-in-progress: true` 加上同一个 `_work` 目录，意味着同一个 ref 上间隔太近的两次推送
会让前一次在构建中途被取消，后一次紧接着在它上面开始。实测见过 `verify.log` 0 字节 + exit 2 的失败。
同一个 ref 连续推送时，等前一个 run 结束更稳。

### 长期出路

1. 等 GitHub 托管镜像带上 Xcode 27，把 `runs-on` 改回 `macos-26`，runner 降级为可选加速；
2. 仓库转回 private + 升级 GitHub Pro，然后自托管 runner 的风险面会小很多（没有陌生 fork）；
3. 自建一台专用机器跑 runner，与开发机隔离。


### 按顺序引入，一次只加一层

| 周次 | 内容 | 为什么这个顺序 |
| --- | --- | --- |
| 第 1 周 | CI（`.github/workflows/ci.yml` 已备好）+ PR 模板 + 分支保护 | 先有闸门，再谈规则 |
| 第 2 周 | SwiftFormat 全仓库格式化一次，之后 CI 拦截 | 纯机械，无争议，先做掉 |
| 第 3 周 | SwiftLint，**只开少量规则** | 见下 |
| 第 4 周 | 收紧直推：见下方"分支保护的现实" | 需要前 3 周已经稳定 |

**分支保护（已启用，2026-10-24）。** 仓库已转为 public，免费计划下也能启用保护。`main` 当前规则：

| 规则 | 状态 |
| --- | --- |
| 必须通过 PR 合并 | **启用**（必需批准数 0——单人无法自审） |
| 管理员同样受限 | **启用**（`enforce_admins`） |
| 禁止强制推送 | **启用** |
| 禁止删除分支 | **启用** |
| 必需状态检查（CI） | **未启用**——等 CI 在真实 runner 上跑通一次再加 |

最后一行是接下来唯一要做的事：`.github/workflows/ci.yml` 还没推送过，检查名在 GitHub 上不存在，现在设成必需会把所有合并永久卡死。顺序必须是"先推送 → 手动跑通 → 再设为必需"。

副作用要记住：公开后 commit 邮箱会进入公开历史，且已经被别人 clone 的内容无法收回。

**SwiftLint 起步规则集**（不要一次全开，否则会得到几千条警告，然后所有人学会忽略它）：

```yaml
file_length: { warning: 1200, error: 2000 }
function_body_length: { warning: 80, error: 150 }
cyclomatic_complexity: { warning: 15, error: 25 }
force_cast: error
force_try: error
todo: warning
```

前三条会立刻让两个巨型文件报错——这是预期的，它们本来就在 §9 的拆分计划里。

---

## 7. AI 生成代码的附加规则

仓库里存在 `codex/` 分支，说明这是日常而非例外。AI 产出的代码在审查中需要额外三条：

1. **PR 描述必须声明**：哪些部分是 AI 生成、你亲自验证了什么、没验证什么。
2. **审查者不得以"看起来对"通过。** 必须有测试、日志或运行证据。AI 写的代码读起来往往比人写的更通顺，这正是它的危险之处。
3. **单次 ≤ 400 行。** AI 最擅长一次改 2,000 行，最不擅长解释为什么这么改。

本仓库中 AI 最容易犯的四类错误，审查时优先盯：

- 编造不存在的 API（尤其是 AVFoundation / SwiftVLC 的冷门方法）。
- 忽略 `@MainActor` 与 `Sendable` 约束，靠 `@unchecked` 蒙混。
- 用 `try?` 把错误吞掉，让失败看起来像成功。
- 往已经超长的文件里继续堆代码（`HomeViewModel` 7,296 行就是这样长出来的）。

另外：AI 生成的注释如果只是复述代码，删掉。注释应该解释"为什么"。

---

## 8. 度量：怎么知道这套东西有用

每季度看一次，不做实时看板（会变成表演）。

| 指标 | 目标 |
| --- | --- |
| PR 变更行数中位数 | ≤ 250 |
| PR 首次响应时长 | ≤ 24 小时 |
| 平均返工轮次 | ≤ 2 |
| 逃逸缺陷（TestFlight / 线上才发现的问题） | 逐季下降 |
| 最大文件行数 | 逐季下降 |

**不统计**评论条数、代码行数产出——它们会鼓励刷评论和堆代码。

---

## 9. 落地路线（4 周）

| 周 | 动作 | 验收 |
| --- | --- | --- |
| W1 | 落地 PR 模板、CI；分支保护已启用（见 §6）；清走根目录的 `temp.md` / `test.md` / `ui-proposal.md` | 第一个 PR 走完全流程 |

> **W1 已完成（2026-10-24）。** `ui-proposal.md` 移入 `design/`；`temp.md` / `test.md` 移到仓库
> 之外的 `~/Documents/taption_encoder-notes/`，并在 `.gitignore` 里加了 `/temp.md`、`/test.md`，
> 防止以后又在根目录生成同名文件被误提交。
>
> 注意：这两个文件在移出前已经在公开历史里存在过（`test.md` 32 个提交、`temp.md` 31 个）。
> `git rm` 只影响 HEAD，历史里仍然可读。实测扫描过它们的内容，暴露的是 **7 个模拟器 UUID 和
> 本地 `/private/tmp/...` 路径**，没有 token、邮箱、真机 UDID 或签名资产。如果要连历史一起清，
> 需要 `git filter-repo` + 强推（所有 SHA 变化、所有 clone 失效），这是另一个决定。

| W2 | 拆两个巨型文件的第一刀：`HomeViewModel` 按职责切出导入 / 编码 / 预览三个协调者（**先只搬不改**）；`CodecRoutePlannerTests` 按主题拆成 8–10 个文件（含 pbxproj 注册） | 两个文件都 < 2,000 行，测试数量不变 |
| W3 | SwiftFormat + SwiftLint 基线，全仓库格式化一次 | CI 能拦住新增违规 |
| W4 | 第一次回顾：看 4 周数据，调整级别定义与清单 | 输出修订版本文档 |

W2 的"先只搬不改"是关键：拆分和改逻辑放在同一个 PR 里，等于把两个高风险变更叠在一起，审查者无法分辨回归来自哪一半。

---

## 10. 反模式

- 2,000 行 PR 配一句 `LGTM`。
- 用 lint 问题淹没真正的并发 bug——审查时间应该花在 §5 上。
- 审查者顺手改代码并直接推 `main`（绕过闸门，比不审更糟）。
- 只在 PR 里讨论架构：架构讨论开 issue，PR 里只谈这次改动。
- 把"以后再说"当结论，不留 issue——等于这件事消失了。
- 用"这个文件本来就长"作为继续往里加代码的理由。
