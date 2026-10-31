# 07 · 原生组件登记表与复用指南

2026-10-31 起，窗口级控件（窗口、标题/副标题、toolbar、菜单栏、侧栏折叠按钮）由宿主 AppKit 实现；内容区仍在 WKWebView。本文是这些组件的登记表：新增 app、改窗口 chrome、或要加一种原生控件时，先查这里，再决定改哪一层。

判断标准不是“看起来像”，而是：按钮、菜单、搜索框、侧栏按钮是 `NSToolbarItem` / `NSMenuToolbarItem` / `NSSearchToolbarItem` 实例；app 只传语义（id、SF Symbol、标题、菜单项、搜索占位、禁用），不写 Swift、不传颜色/字号/边距。

## 1. 分层

| 层 | 可以做什么 | 不可以做什么 |
|---|---|---|
| app 页面 `[TS]` | 组合内容、声明 toolbar 语义、注册菜单栏命令、开关侧栏 | 创建 AppKit 视图、写 toolbar CSS、写 per-app Swift |
| 宿主 `[Swift]` | 创建窗口/toolbar/菜单/面板、提供系统能力 | 认识某个 app 的业务、写 app 专属分支 |
| 内容区 | 列表、消息、Markdown、Composer、设置表单 | 自绘标题条/工具栏 |

新增一种原生控件时：**ShellCore 加模型 → ShellUI 加工厂 → ui/ 加类型/API → 本文加一行 → 补测试**。所有 app 立刻可用；不新增 app 专属 Swift。

## 2. app 可用的原生能力 `[TS]`

这些是页面里唯一能触达原生窗口控件的入口，全部从 `@wisp/ui` 导入。

| 入口 | 位置 | 作用 | 用法 |
|---|---|---|---|
| `Window` | `ui/src/components.tsx` | 页面根布局；设置原生 `window.title` / `subtitle`；控制侧栏列是否显示 | `<Window title subtitle columns sidebar>` |
| `Sidebar` / `Content` / `Detail` | 同上 | 内容列；列本身没有标题/工具栏 | 只放 children |
| `useToolbar` | `ui/src/hooks.ts` | 声明本窗口原生 toolbar；host 回传动作/搜索 | `useToolbar(spec, handlers, onSearch?)` |
| `useTabs` | 同上 | 声明原生设置分类标签并接收选中 id；`<Settings>` 内部使用 | `useTabs(tabs, onSelect)` |
| `useSidebar` | 同上 | 侧栏可见状态 + 切换；持久化到 app 设置，响应 ⌃⌘S | `const [visible, toggle] = useSidebar()` |
| `useCommands` | 同上 | 注册原生菜单栏命令（文件/显示） | `useCommands([{ id, menu, title, shortcut, run }])` |
| `Icon` | `ui/src/components.tsx` | SF Symbol 模板图，宿主生成 PNG，页面用 CSS mask 着色 | `<Icon symbol="plus" />` |
| `ContextMenu` | 同上 | 右击包住的内容时，由宿主弹原生 `NSMenu` | `<ContextMenu items={[{ id, title, disabled?, destructive?, onAction }]}>` |
| `setContentHeight` | `ui/src/bridge.ts` | 设置窗口按内容高度做原生动画（设置窗口） | `setContentHeight(px)` |
| `openSettings` | `ui/src/bridge.ts` | 打开本 app 的设置窗口 | `openSettings()` |

### 2.1 `Window` 的窗口级属性

```tsx
<Window title="All" subtitle="3 items" columns={3} sidebar={sidebar}>
  <Sidebar>…</Sidebar>
  <Content>…</Content>
  <Detail>…</Detail>
</Window>
```

- `title` / `subtitle` 走 `WindowRequest.title`，最终写 `window.title` / `window.subtitle`；页面不要画标题。
- `columns={2}` 隐藏 `Content` 列，`columns={3}` 显示三列。
- `sidebar={false}` 给根节点加 `sidebar-hidden`，侧栏列 `display:none`；切换由原生 toolbar 的 `sidebar` item 触发。
- `Sidebar` / `Content` / `Detail` 只有 children，没有 `title` / `subtitle` / `toolbar` 属性。

### 2.2 `useToolbar`

```tsx
const [sidebar, toggleSidebar] = useSidebar();

useToolbar(
  {
    leading: [
      { id: "sidebar", sidebar: true, help: "Toggle Sidebar" },
      { id: "new", symbol: "square.and.pencil", help: "新建" },
    ],
    trailing: [
      { id: "sort", symbol: "arrow.up.arrow.down", menu: [
        { id: "sort-az", title: "Title A–Z" },
        { id: "sort-za", title: "Title Z–A" },
      ]},
      { id: "add", symbol: "plus", help: "New item" },
      { id: "search", search: true, placeholder: "Search" },
    ],
  },
  { sidebar: toggleSidebar, new: newItem, "sort-az": …, "sort-za": …, add },
  setQuery,
);
```

规则：

- `id` 在页面内唯一；菜单项 id 也唯一。宿主只回传 id，不解释业务。
- `leading` 在红绿灯右侧；`trailing` 靠右；宿主在两者之间插 flexible space。
- `disabled` 映射到原生 item / menu item 的 enabled 状态；`help` 映射为 tooltip。
- `destructive` 目前只是语义提示，Phase 1 用普通 `NSMenuItem`。
- 搜索框文本归 `NSSearchField` 所有；spec 不要带 `value`，页面通过 `onSearch` 收文本，不要回写。
- `useToolbar` 在挂载时至少发一次（空 spec 也发）；spec JSON 变化才重发，搜索输入不重建。
- 不需要 toolbar 的页面也调用 `useToolbar({})`，保证主窗口标题栏高度一致。

### 2.3 toolbar item 类型

| 类型 | TS 字段 | 宿主控件 | 说明 |
|---|---|---|---|
| 按钮 | `{ id, symbol, help?, disabled? }` | `NSToolbarItem(isBordered:)` | SF Symbol + tooltip + target/action |
| 菜单按钮 | `{ id, symbol?, title?, menu }` | `NSMenuToolbarItem` + `NSMenu` | 每个 `NSMenuItem.representedObject` 是页面 id |
| 搜索 | `{ id, search: true, placeholder? }` | `NSSearchToolbarItem` + `NSSearchField` | 文本变化回传 `toolbarSearch` |
| 侧栏折叠 | `{ id, sidebar: true, help? }` | `NSToolbarItem`（`sidebar.left`） | 点击回传 `toolbarAction`，页面用 `useSidebar` 切列 |
| 设置分类标签 | `ToolbarSpec.tabs: { id, title, symbol?, selected? }[]` | 每个 tab 一个 `NSToolbarItem` + `selectedItemIdentifier` | 点击回传 `tabSelected`；选中变化不重建 toolbar |

### 2.4 `useCommands` 与菜单栏

```tsx
useCommands([{ id: "new", menu: "file", title: "新建对话", shortcut: "cmd+n", run: newConversation }]);
```

- `menu` 只支持 `file` / `view`；菜单栏的 app / 编辑 / 窗口 / 帮助骨架由宿主固定。
- `shortcut` 形如 `cmd+n`、`cmd+shift+n`、`cmd+,`；实际菜单项由 `MenuBarController` 创建。
- 菜单命令和 toolbar 动作是两条通道：同一个函数可以同时绑到 `useCommands` 的 `run` 和 `useToolbar` 的 handler。

## 3. 宿主可复用的原生组件 `[Swift]`

### 3.1 窗口

`WindowFactory` 是**唯一**创建 `NSWindow` / `NSPanel` 的地方；app 代码不直接 `NSWindow(...)`。

| 方法 | 产出 | 用途 |
|---|---|---|
| `makeAppWindow(for:content:)` | `NSWindow` | app 主窗口：`.titled` + `.fullSizeContentView` + `titlebarAppearsTransparent` + `toolbarStyle = .unified` |
| `makeSettingsWindow(for:content:)` | `NSWindow` | app 设置窗口：原生标题栏 + 原生分类标签 toolbar；高度由页面 `height` 控制 |
| `makeLauncherPanel(content:)` | `NSPanel` | 浮窗启动器：`.nonactivatingPanel` + 透明背景，`LauncherPanel.canBecomeKey = true` |
| `makeSettingsWindow(panes:)` | `NSWindow` | 壳自己的设置：`NSTabViewController(tabStyle: .toolbar)` + SwiftUI 表单 |

```swift
let window = WindowFactory().makeAppWindow(for: descriptor, content: pageController)
```

### 3.2 toolbar

`NativeToolbarController`（`ShellUI/Toolbar/NativeToolbarController.swift`）是唯一 toolbar 实现，不认识任何 app。

```swift
let toolbar = NativeToolbarController(
    onAction: { id in
        connection.push(["type": .string("toolbarAction"), "id": .string(id)])
    },
    onSearch: { text in
        connection.push(["type": .string("toolbarSearch"), "text": .string(text)])
    })
toolbar.install(on: window)          // 主窗口 viewDidAppear 时调用；空 spec 也装
toolbar.apply(spec)                  // 收到 {type:"toolbar", spec} 后调用
```

行为：

- `NSToolbar` + `toolbarStyle = .unified`；`leading` item 标记 `isNavigational` 才会排在红绿灯一侧。
- 结构变化才换 `NSToolbar`；只有 `disabled` 变化时原地更新 item/menu。
- 空 spec 保留一个 flexible space，保证标题栏高度一致。
- 搜索文本由 controller 暂存并在重建时恢复；不要每敲一个字重建 toolbar。
- 菜单的每个 `NSMenuItem` 用 `representedObject` 存页面 id；点击只回传 id。
- `tabs` 的每个 pane 是一个 `NSToolbarItem`（SF Symbol + 标题），在 `toolbarSelectableItemIdentifiers` 里登记，选中态由 `NSToolbar.selectedItemIdentifier` 画；点击回传 `tabSelected`，不让页面传颜色/尺寸。
- 设置窗口的 toolbar 用 `.preference` 样式：标题栏一行、标签栏一行，Web 内容在其下，不会被顶到标题栏下面。

`ToolbarSpec` 模型在 `ShellCore/Model/ToolbarSpec.swift`：纯 `Decodable`，不 import AppKit。`WindowRequest.toolbar(ToolbarSpec)` 由 `AppSession` 解码后交给 `AppPageController`。

### 3.3 菜单栏与状态栏

| 组件 | 位置 | 用途 | 用法 |
|---|---|---|---|
| `MenuBarController` | `ShellPlatform/Menu` | 根据 `MenuModel` 重建 `NSApp.mainMenu` | `menuBar.rebuild(model)` |
| `MenuModel` / `MenuCommand` | 同上 | app 名、命令、设置、退出、语言 | `MenuCoordinator` 组装；app 命令经 `useCommands` 进入 |
| `StatusItemController` | `ShellPlatform/Presentation` | 菜单栏图标，左键动作/右键菜单 | 壳启动时创建；app 不直接用 |
| `HotKeyCenter` | 同上 | Carbon 全局快捷键 | 壳设置里注册；app 不直接用 |

`MenuBarController` 固定提供 app / 文件 / 编辑 / 显示 / 窗口 / 帮助骨架；app 只能通过 `useCommands` 往文件/显示里加项。

显示菜单的“显示/隐藏侧栏 ⌃⌘S”使用宿主自定义 action：`AppSession.toggleSidebar()` 发 `sidebarToggle`，页面用 `useSidebar` 的同一个 toggle 处理。它和 toolbar 的 `sidebar` item 共用页面 handler，见第 5 节。

### 3.4 设置、启动器、设计令牌

| 组件 | 位置 | 用途 | 用法 |
|---|---|---|---|
| `SettingsPane` | `ShellPlatform/Windows` | 壳设置的一个 tab | `SettingsPane(id:title:symbol:content:)` |
| `SettingsTabController` | 同上 | toolbar 风格 tab 的标题同步；内部 | 由 `WindowFactory.makeSettingsWindow(panes:)` 使用 |
| `ShellPresenter` | `ShellPlatform/Presentation` | 浮窗/壳设置窗口的显示与失焦关闭 | `showLauncher()` / `showSettings()` |
| `LauncherView` | `ShellUI/Launcher` | 浮窗根视图 | `NSHostingController(rootView: LauncherView(state:send:))` |
| `GridLauncher` | 同上 | 图标网格启动器；内部 | 由 `LauncherView` 选择 |
| `AppIconView` | `ShellUI/Components` | app 图标渐变块 + SF Symbol | `AppIconView(descriptor, size:)` |
| `shellPanel()` | `ShellUI/DesignSystem/GlassStyles` | 浮窗玻璃材质 | `.shellPanel()` |
| `ShortcutRecorder` | `ShellUI/Settings` | 快捷键录制控件；内部 | 壳设置表单用 |
| `SymbolImage` | `ShellUI/Web` | SF Symbol → 模板 PNG，给 `Icon` 用；内部 | `SymbolImage.png(named:)` |
| `Spacing` / `Radius` / `IconSize` / `AppTint.color` | `ShellUI/DesignSystem` | 尺寸、圆角、图标、tint 令牌 | 宿主视图只用这些，不写魔法数 |

## 4. 当前原生 / Web 边界

| 部分 | 当前实现 | 归属 |
|---|---|---|
| 窗口、红绿灯、拖动、双击缩放 | `NSWindow` | 原生 |
| `window.title` / `subtitle` | AppKit | 原生 |
| `NSToolbar` / `NSToolbarItem` | `NativeToolbarController` | 原生 |
| toolbar 按钮 / 菜单 / 搜索 | `NSToolbarItem` / `NSMenuToolbarItem` / `NSSearchToolbarItem` | 原生 |
| 侧栏折叠按钮 | `NSToolbarItem` + `sidebar.left` | 原生 |
| 侧栏列的显示/收起布局 | `Window sidebar` + CSS 宽度/透明度过渡 | Web（toolbar 按钮原生） |
| 侧栏折叠状态 | app 设置 `sidebarVisible` | Web 调用宿主设置通道 |
| 显示菜单 ⌃⌘S | 原生菜单项 → `sidebarToggle` → `useSidebar` | 原生菜单 + Web 布局 |
| 菜单栏、状态栏 | `MenuBarController` / `StatusItemController` | 原生 |
| 壳设置窗口、浮窗启动器 | SwiftUI + `NSTabViewController` | 原生 |
| app 设置窗口标题栏 | 原生标题栏 | 原生 |
| app 设置分类标签 | 原生 `NSToolbarItem` + `selectedItemIdentifier` | 原生 |
| app 设置表单控件 | Web | Web（阶段 5 再议） |
| 侧栏行/列表、内容列表、详情 | WKWebView + 设计系统 | Web |
| 消息、Markdown、Composer | WKWebView | Web |
| Agent 侧栏搜索 | Web `Search` | Web |
| 页内 `ContextMenu` | 宿主 `NSMenu`（共享 `NativeMenuFactory`） | 原生 |
| 页内 `Menu` 下拉 | Web popover | Web |
| Composer 发送/加号/模型菜单 | Web | Web |

## 5. 原生侧栏 / NSSplitView：设计评估与结论

2026-10-31 阶段 3 先做设计，结论：**继续单 WebView，选 C**；不引入 `NSSplitView` 或第二个 `WKWebView`。窗口仍由 `WindowFactory` 创建，侧栏布局仍是一份 Web CSS。

### 5.1 三个选项

| | A. 原生侧栏 + Web 详情 | B. 侧栏再放一个 WKWebView | C. 单 WebView + 补折叠体验 |
|---|---|---|---|
| 每窗口 WebContent | 1 个（详情） | 2 个 | 1 个 |
| 内存 | 原生 `NSOutlineView` 很轻，详情 WebView 不变 | 空侧栏页约 +24 MB；长列表可到 +90 MB（01 §2） | 不变 |
| 布局真相 | 原生 split + Web 详情，两套 | 原生 split + 两个 Web 页 | 一套 Web CSS |
| 桥 / 同步 | 新侧栏协议；选中、搜索、右键、行内改名都要跨桥 | 两个 JS 上下文；选中/搜索/滚动/数据要在两页同步 | 无新数据协议；只加一条 `sidebarToggle` |
| 通用数据模型 | 要覆盖分组、行、图标、计数、选中、右键、搜索、空状态、tiles/卡片 | 同 A，且两页各存一份状态 | 不需要 |
| per-app Swift | 模型足够通用就不需要；但覆盖不了时会被迫写 | 同样有该风险 | 不需要 |
| 原生收益 | 分隔线拖动、折叠动画、材质边界、原生行 | 同 A | 只有折叠动画/持久化/菜单快捷键 |

A 的通用模型草案（仅示意）：

```text
SidebarSpec { sections: [{ id, title, rows: [
  { id, title, subtitle?, symbol?, badge?, selected, menu?, search? }
]}]}
```

它覆盖不了示例的 `SidebarTiles` 两列卡片、Agent 的分组搜索和行内改名；要覆盖就得继续加 `tile` / `editing` / `filter` 等原生行类型，这已经是内容控件原生化的 C 方向，需要单独决策。

### 5.2 为什么不做 A/B

1. **A 是内容控件迁移，不是窗口 chrome**。侧栏行、分组、搜索、右键、行内改名目前都由 app 的 TS 组合；改成原生列表就得定义一套覆盖所有 app 的通用模型，或者给每个 app 写 Swift，后者违反“不做 per-app Swift”。
2. **A 会制造两个布局真相**。原生 split 负责侧栏宽度/分隔线，Web 负责详情内部的列宽、滚动、`--titlebar` inset；窗口 resize、折叠、材质边界都要两边对齐。当前一个 CSS 就能保证。
3. **B 与单 WebView 架构冲突**。每个窗口多一个 WebContent 进程，空页约 24 MB，长列表更高；还要在两个页面间同步选中对话、搜索词、新建/删除、右键菜单和滚动位置，收益只是原生分隔线和折叠动画。
4. **C 已覆盖本阶段真正缺的东西**：折叠动画、持久化、⌃⌘S 菜单。它们不需要拆窗口。

### 5.3 C 的实现（本阶段）

- **折叠动画**：`Window sidebar` 只切 class；侧栏宽度/透明度做 200ms 过渡，`overflow: hidden`，隐藏后用 `visibility: hidden` 让内容不可聚焦；`prefers-reduced-motion` 时关闭过渡。没有 `display:none`，详情列平滑重排。
- **持久化**：`useSidebar` 用 app 设置里的 `sidebarVisible` 保存开关，重开窗口保持；仍是 per-app，不是 per-window。
- **⌃⌘S**：宿主“显示”菜单的项改为自定义 action，调 `AppSession.toggleSidebar()`，经 `{type:"sidebarToggle"}` 到页面；`useSidebar` 用同一个 `toggle` 处理，和 toolbar 的 `sidebar` item 完全共用。设置窗口没有主页面时不发。
- 不新增 `NSSplitView`，不改 `WindowFactory`，不写 per-app Swift，内存不变。

### 5.4 已知限制与重评条件

限制：没有原生分隔线拖动；侧栏材质边界仍由 Web 层叠决定；折叠状态是 app 级而非窗口级；侧栏内容仍是 Web。

重评条件：侧栏内容确定要改成原生列表（或能接受每窗口两个 WebView），并且需要原生拖动/折叠/材质；届时的路径是 `NSSplitViewController` + 原生侧栏视图/第二个 WebView → toolbar 的 `sidebar` item 改绑 `toggleSidebar(_:)` → 显示菜单复用同一 action → 删除 `Window sidebar` 的 CSS 开关。**不要只在外层套一个 `NSSplitView` 而内容仍是一个整页 WebView。**

## 6. 后续开发：仍是 Web 的部分

### Phase 2

1. **设置窗口分类标签栏（已完成）**：`<Settings>` 的 Web `.tabs` 已改为原生 toolbar tab；新增 `ToolbarSpec.tabs`、`useTabs` 和 `tabSelected` 回传。设置表单仍留在 Web。
2. **页内 `ContextMenu`（已完成）**：右击时页面把 `{items:[{id,title,destructive,disabled}]}` 发给宿主，宿主用 `NSMenu` 在鼠标位置弹出，选中回传 `contextMenuAction`。Escape/点击外部/深色模式由 AppKit 处理；`Menu` 下拉仍留 Web。

### 后续 C 方向（需要先决策）

- 原生侧栏 / `NSSplitView`（见第 5 节）。
- 原生列表、内容列表、详情。
- 原生 Composer、发送/加号/模型菜单。
- 原生 Markdown / 消息渲染。
- 原生 Agent 侧栏搜索。
- 原生设置表单控件（开关/下拉/输入框）——需要通用表单模型，否则会变成 per-app Swift。

这些不做进 Phase 1/2 的默认范围；每次只选一个，先写设计再动代码。

## 7. 新增原生控件的检查清单

- [ ] `ShellCore` 加 `Sendable` / `Equatable` / `Decodable` 模型，不 import AppKit。
- [ ] `ShellUI` 加工厂（优先扩 `NativeToolbarController` 的 item kind，而不是新建控制器）。
- [ ] `ui/src/bridge.ts` 加类型/消息，`ui/src/hooks.ts` 或组件加语义入口。
- [ ] `NativeToolbarController` 不出现任何 app id / app 名称判断。
- [ ] 只回传 id / 文本，不让页面传样式。
- [ ] 测试：模型解码、桥路由、必要的行为测试。
- [ ] 本文第 2/3/4 节加行；`docs/06-native-toolbar.md` 如涉及契约同步更新。
- [ ] 截图只截关键状态；`make lint`、`make test`、`make build`、`make release`。
- [ ] 不做 per-app Swift，不为一个 app 加特例。
