# 08 · 后续迁移到原生的新会话提示词

本文是给新会话直接复制的提示词模板。每个提示词都假设从仓库根目录开始，并且遵守 `docs/06-native-toolbar.md` 的原生/Web 边界。

通用约定（每个提示词都已内置）：

- 只做提示词里写的范围，不做无关重构。
- 不写 per-app Swift；宿主不认识任何 app id / app 名称。
- 页面只传语义，不传颜色、字号、边距。
- 验证从简：跑 `make lint`、`make test`、`make build`、`make release`；只截 1–2 张关键图确认结构，不用反复看像素和交互，用户自己会看更快。

## 1. Phase 2：设置分类标签栏改原生

```text
在 /Users/jgao/Dsh/mac-app-opus 继续 Wisp Loom。先读 AGENTS.md、docs/01-architecture.md 第 2 节、docs/02-app-protocol.md 第 2 节、docs/03-native-ui.md 第 3/4 节、docs/06-native-toolbar.md、docs/07-native-components.md。

目标：把 app 设置窗口顶部的 Web 分类标签（ui/src/components.tsx 的 Settings 里的 .tabs）迁成原生 NSToolbar，复用 NativeToolbarController 和现有 item 工厂，不新写 per-app Swift。

要求：
- 设置窗口仍是“原生标题栏 + 原生 tab 栏”；不要因为加 toolbar 把表单内容顶到标题栏下面。
- 新增通用 tabs 语义（pane id/title/symbol/selected）和选择回传，app 只声明 pane 列表；设置表单控件继续用 Web，不在本次迁。
- 保留现有窗口高度动画和 window.title 行为；示例与 Agent 的设置页都要工作。
- ShellCore 模型不 import AppKit；NativeToolbarController 不认识任何 app。
- 更新 docs/03、docs/06、docs/07 和测试。

验证从简：make lint && make test && make build && make release；用 scripts/shot.sh 截示例设置和 Agent 设置各一张（深浅色可选），不用反复视觉核对，用户自己会看更快。
```

## 2. Phase 2：页内 ContextMenu 改原生 NSMenu

```text
在 /Users/jgao/Dsh/mac-app-opus 继续 Wisp Loom。先读 AGENTS.md、docs/02-app-protocol.md 第 2 节、docs/03-native-ui.md 第 2/4 节、docs/06-native-toolbar.md 第 7 节、docs/07-native-components.md。

目标：把页内右键菜单 ContextMenu 从 Web popover 迁到原生 NSMenu：页面右击时发菜单项（id/title/destructive/disabled），宿主在鼠标位置弹出 NSMenu，选中后只回传 id。

要求：
- 复用 toolbar 菜单的 NSMenuItem → representedObject → id 思路；宿主通用，不认 app。
- 本次只迁 ContextMenu；页内 Menu 下拉可以先保留 Web。
- 不改内容区其他控件，不写 per-app Swift，不让页面传样式。
- 处理 Escape/点击外部关闭、深色模式、禁用项；菜单项 id 在页面内唯一。
- 更新 docs/03、docs/06、docs/07、测试（至少桥/消息测试）。

验证从简：make lint && make test && make build && make release；截 1 张 Agent 侧栏右键菜单的图确认是原生 NSMenu，不用反复看交互，用户自己会看更快。
```

## 3. 原生侧栏 / NSSplitView（先设计，再决定实现）

```text
在 /Users/jgao/Dsh/mac-app-opus 继续 Wisp Loom。先读 AGENTS.md、docs/01-architecture.md 第 2 节、docs/03-native-ui.md 第 1 节、docs/06-native-toolbar.md、docs/07-native-components.md 第 5 节（为什么现在不用 NSSplitView）。

目标：评估并（如果结论成立）把侧栏迁移到原生 NSSplitViewController，让侧栏可拖动、可折叠、状态按窗口持久化，同时保持内容区 Web。

先写一页设计（docs/09-native-sidebar.md）比较：
A. 原生侧栏视图（NSOutlineView 等）+ Web 详情；
B. 侧栏再放一个 WKWebView（每窗口两个 WebContent 进程）；
C. 继续单 WebView，只补折叠动画/持久化/⌃⌘S 菜单。
写清内存、桥、同步、每 app 数据模型、是否违反“不做 per-app Swift”。

如果选 A/B：按设计实现，窗口仍由 WindowFactory 创建，toolbar 的 sidebar item 绑 toggleSidebar，显示菜单的 ⌃⌘S 复用同一 action；不做内容区其他控件的原生化。
如果结论是代价过大：只实现 C 的低风险部分，并在 docs/07 里更新结论，不硬上 NSSplitView。

验证从简：make lint && make test && make build && make release；截折叠/展开各一张图即可，不用反复看动效，用户自己会看更快。
```

## 4. 内容控件原生化 PoC（一次只做一个）

```text
在 /Users/jgao/Dsh/mac-app-opus 继续 Wisp Loom。先读 AGENTS.md、docs/01-architecture.md 第 2 节、docs/03-native-ui.md 第 4 节、docs/06-native-toolbar.md 第 9 节、docs/07-native-components.md 第 6 节。

目标：从“仍是 Web 的内容控件”里选一个做最小原生化 PoC，优先级建议：Composer 的发送/加号/模型菜单 → Agent 侧栏搜索 → 列表/消息。不要一次性全迁。

要求：
- 先写半页设计：为什么这个控件需要原生、对内容 WebView 的影响、是否通用、是否会导致 per-app Swift；结论不成立就停在设计，不硬做。
- 如果做：只改一个控件，保持其他内容 Web；宿主提供通用能力，页面只传语义；不传样式。
- 不新增第三方依赖，不改 Phase 1 的 toolbar/标题/侧栏折叠行为。
- 更新 docs/07 的边界表和测试。

验证从简：make lint && make test && make build && make release；只截该控件一张关键图，不用反复看，用户自己会看更快。
```

## 5. 设置表单控件原生化（通用表单模型）

```text
在 /Users/jgao/Dsh/mac-app-opus 继续 Wisp Loom。先读 AGENTS.md、docs/02-app-protocol.md 第 2 节、docs/03-native-ui.md 第 3/4 节、docs/07-native-components.md。

目标：评估把 app 设置表单（Toggle / Picker / TextField / SecureField）迁到原生 AppKit/SwiftUI，同时避免 per-app Swift。

先写设计：定义一个通用表单 schema（field id/type/title/value/options/secure），宿主渲染原生控件，页面只发 schema 和值；比较它与继续用 Web 表单的代价。如果 schema 能覆盖示例和 Agent 的通用/模型设置，再实现一个 pane 的 PoC；否则停在设计并说明。

要求：
- 不迁设置分类标签（那是另一个任务），不改窗口高度逻辑。
- 不泄露密钥明文；沿用现有 Keychain/设置通道。
- 不写 per-app Swift。
- 更新 docs/07 和测试。

验证从简：make lint && make test && make build && make release；截一张设置页图确认控件是原生即可，不用反复看，用户自己会看更快。
```
