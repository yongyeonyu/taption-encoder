## 这个 PR 做了什么

<!-- 一句话。说不清就说明该拆了。 -->

## 为什么要做

<!-- 关联 issue / 用户反馈 / 缺陷编号 -->

## 风险级别

- [ ] **T1 核心** — `Core/Codecs` / `Core/Encoding` / `Core/VideoCore` / `Core/MediaInspection` / `Vendor`
- [ ] **T2 功能** — `Features` / `Shared` / 扩展 target
- [ ] **T3 低风险** — 资源 / 文案 / 文档 / 构建脚本

> 分级依据见 [docs/code-review/README.md](../docs/code-review/README.md) §2。

## 验证

- [ ] 单元测试全过（当前 478 个）
- [ ] 模拟器运行过（附截图或录屏）
- [ ] **真机验证（T1 必填）**：设备 / iOS 版本 / 结果
- [ ] 新增测试：文件 + 用例名

## 自检（对照 [checklist.md](../docs/code-review/checklist.md)）

- [ ] 变更 ≤ 400 行，或已说明为何不能拆
- [ ] 无调试代码、无注释掉的代码、无新增 `print(`
- [ ] 无新增强制解包 / `try!` / `as!`
- [ ] 新增文件已注册到 `project.pbxproj`
- [ ] 失败路径已处理：状态回滚、临时文件清理、界面不停在 loading

## 若由 AI 生成

- [ ] 已注明哪些部分由 AI 生成
- [ ] 已注明我亲自验证了什么、没验证什么
- [ ] 变更 ≤ 400 行

## 审查者

@
