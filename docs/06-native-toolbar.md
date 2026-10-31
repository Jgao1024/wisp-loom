# 06 · 原生窗口控件与 Toolbar

2026-10-31 决策：**窗口级控件必须是真原生**。上一版用 CSS 仿 `NSToolbar` / `NSButton` / `NSSearchField`，截图放到 Notes 旁边就能看出是网页画的（bezel、悬停、焦点、菜单跟踪、搜索框都不是系统的）。这一版把窗口级控件收回宿主，内容区仍留在 WKWebView。

判断标准不是“看起来像”，而是：**按钮、菜单、搜索框是 `NSToolbarItem` / `NSButton` / `NSMenu` / `NSSearchField` 实例**，由 AppKit 画状态。内容区（列表行、消息、Markdown、Composer）仍是 Web，这是本阶段明确接受的边界。

## 1. 原生 / Web 分工

| 部分 | Phase 1 实现 | 原生？ |
|---|---|---|
| 窗口、红绿灯、拖动/双击缩放 | AppKit `NSWindow` | 是 |
| 窗口标题 / 副标题 | `window.title` / `window.subtitle` | 是 |
| 标题栏、工具栏 | `NSToolbar` + `NSToolbarItem` | 是 |
| toolbar 按钮 | `NSToolbarItem(isBordered: true)` + SF Symbol | 是 |
| toolbar 菜单 | `NSMenuToolbarItem` + `NSMenu` | 是 |
| toolbar 搜索 | `NSSearchToolbarItem` + `NSSearchField` | 是 |
| 菜单栏、状态栏图标 | AppKit | 是 |
| 壳设置窗口、浮窗启动器 | SwiftUI | 是 |
| 侧栏行、内容列表、详情 | WKWebView + 设计系统 | 否 |
| 消息、Markdown、Composer | WKWebView + 设计系统 | 否 |
| app 内 `Menu` / `ContextMenu` 弹出菜单 | HTML popover（Phase 2 再迁原生） | 否 |
| 设置窗口的分类标签栏 | Web 标签（Phase 2 迁 `NSToolbar`） | 否 |
| 设置表单控件（开关/下拉/输入框） | Web（不属本阶段） | 否 |

规则：

1. **页面不再画标题条/工具栏**，也不再有拖动、双击缩放的页面逻辑；这些由 `NSToolbar` 和 `NSWindow` 负责。
2. 页面只声明 toolbar 的语义（id、SF Symbol、标题、菜单项、搜索占位、禁用），由宿主决定控件和样式。app 不能传颜色、字号、边距。
3. `Content` / `Detail` / `Sidebar` 只是内容列；不再有 `title`、`subtitle`、`toolbar` 属性。窗口标题统一走 `Window title/subtitle`。
4. 内容区控件（Composer 的发送/加号/模型菜单、侧栏搜索、页内菜单）仍是 Web，不属于 Phase 1。要做原生内容控件是更大的 C 方向，另议。

## 2. 复用架构

```
app TS
  └─ useToolbar(spec, handlers, onSearch)        只声明，不写样式
       └─ ui/bridge  {type:"toolbar", spec}
            └─ AppSession → WindowRequest.toolbar
                 └─ ShellUI.NativeToolbarController（唯一实现，不认识任何 app）
                      └─ NSToolbar / NSToolbarItem / NSMenuToolbarItem / NSSearchToolbarItem
                           └─ 点击/搜索 → {type:"toolbarAction"/"toolbarSearch"} → 页面 handler
```

一次实现的复用面：

| 能力 | 宿主做一次 | 每个 app 只写 |
|---|---|---|
| toolbar 容器、顺序、flexible space、标题区 | `NativeToolbarController` | — |
| 图标按钮、悬停/按下/焦点/tooltip | `NSToolbarItem(isBordered:)` | `id` `symbol` `help` |
| 菜单按钮、菜单项、禁用 | `NSMenuToolbarItem` / `NSMenu` | menu 项 + id |
| 搜索框 | `NSSearchToolbarItem` | `placeholder` + `onSearch` |
| 标题/副标题 | `window.title/subtitle` | `title` `subtitle` |
| 动作回传、handler 注册 | 桥 + `useToolbar` | `id → function` |
| 设置标签栏（Phase 2） | 复用同一 item 工厂加 `tabs` | pane 列表 |
| 原生右键菜单（Phase 2） | 复用同一 menu 模型 | items |

新增一种原生控件（例如 segmented group、toggle）时：**在宿主和 SDK 各加一次**，所有 app 立刻可用；app 不能自己发明原生控件。Phase 1 只做 button / menu / search 三种，等真实 app 用到再加 group、toggle，避免过度设计。

## 3. `ToolbarSpec`

TS 类型（`ui/src/bridge.ts`）：

```ts
export interface ToolbarMenuItem {
  id: string;
  title: string;
  destructive?: boolean;   // 宿主尽力而为；Phase 1 用普通 NSMenuItem
  disabled?: boolean;
}

export interface ToolbarItem {
  id: string;
  symbol?: string;         // SF Symbol
  title?: string;          // 菜单按钮的标题；纯图标按钮可省
  help?: string;           // tooltip
  disabled?: boolean;
  menu?: ToolbarMenuItem[];// 有 menu 时是菜单按钮
  search?: boolean;        // true 时是搜索框
  placeholder?: string;
}

export interface ToolbarSpec {
  leading?: ToolbarItem[];  // 红绿灯右侧，侧栏上方
  trailing?: ToolbarItem[]; // 右侧，搜索一般放最后
}
```

约束：

- `id` 在页面内唯一；菜单项的 id 也唯一。宿主只回传 id，不解释含义。
- 搜索项的文本归原生 `NSSearchField` 所有；spec 里不要带 `value`，否则每敲一个字都会重建 toolbar。页面通过 `onSearch` 收文本。
- spec 只在结构变化时重建 toolbar；搜索输入不重建。
- 一个窗口只有一个 toolbar。`leading` 和 `trailing` 之间由宿主插入 flexible space，trailing 靠右。
- 不需要 toolbar 的页面也要调用 `useToolbar({})`，保证窗口有统一的原生标题栏高度。

页面写法：

```tsx
useToolbar(
  {
    leading: [{ id: "new", symbol: "square.and.pencil", help: "新建对话" }],
    trailing: [
      { id: "more", symbol: "ellipsis", menu: [
        { id: "rename", title: "重命名" },
        { id: "copy", title: "复制为 Markdown" },
        { id: "delete", title: "删除", destructive: true },
      ]},
      { id: "agent", title: "Wisp Agent", symbol: "person.crop.circle", menu: agentItems },
      { id: "share", symbol: "square.and.arrow.up", help: "导出" },
      { id: "search", search: true, placeholder: "搜索对话" },
    ],
  },
  { new: newConversation, rename: startRename, copy: copyMarkdown, delete: removeActive, share: copyMarkdown },
  setQuery,
);
```

## 4. 页面桥消息

页面 → 宿主（新增一行）：

| `type` | 字段 | 说明 |
|---|---|---|
| `toolbar` | `spec` | 设置/更新本窗口的原生 toolbar；`spec` 结构见上 |

宿主 → 页面（新增两行）：

| `type` | 字段 | 说明 |
|---|---|---|
| `toolbarAction` | `id` | toolbar 按钮/菜单项被点击 |
| `toolbarSearch` | `text` | 原生搜索框文本变化 |

- 仍用 `{type:"title", title, subtitle}` 更新窗口标题/副标题，由原生 toolbar 显示；页面不再绘制标题。
- 动作和搜索走现有 `window.__wisp_recv` 批量通道，不新增 WebKit handler。
- `useToolbar` 在挂载时 `setToolbar(spec)`，并把 `handlers` / `onSearch` 存进 ref；宿主回传时按 id 调最新闭包。
- 宿主没有回传“toolbar 已应用”，页面不需要等待。

## 5. 布局与外观

- 窗口仍是 `.titled + .fullSizeContentView`，WebView 铺满；`NSToolbar` 透明地盖在顶部。
- 页面根节点去掉标题条；每列加顶部 inset（`--titlebar`，Phase 1 取 52pt，截图核对原生 toolbar 实际高度后校准）。
- 列的背景仍然铺到顶部：侧栏透明，露出 `NSVisualEffectView(.sidebar)`；内容/详情 `Canvas` 一直画到窗口顶，所以 toolbar 后面的左右底色和系统 app 一致。
- 原生 toolbar 负责拖动、双击缩放、标题/副标题、按钮 hover/按下/焦点、菜单跟踪、搜索框焦点。
- 页面里不要再放任何“标题条/工具栏”组件或拖拽逻辑。`ToolbarGroup` 删除；`Search` 只用于内容区（例如 Agent 侧栏搜索）。
- 内容列不再有 `title/subtitle/toolbar`。窗口级标题统一用：

```tsx
<Window title={active.title} subtitle={`${active.agent} · ${active.model}`} columns={2}>
```

三栏示例的标题就是内容列当前分组，例如 `All` / `3 items`；内容列顶部不再重复一遍。

## 6. 每个 app 要写什么

只写两样：

1. `Window title/subtitle`（窗口级标题）；
2. `useToolbar(spec, handlers, onSearch?)`（item 列表 + id → handler）。

不写 Swift、不写 toolbar CSS。示例与 Agent 的迁移：

- 示例：title = 当前分组，subtitle = 数量；toolbar = 搜索（trailing）、排序菜单、新增按钮（leading 或 trailing）；原来的页内搜索/排序/加号删除。
- Agent：title = 当前对话，subtitle = `Agent · Model`；toolbar leading = 新建对话，trailing = ⋯ 菜单（重命名/复制/删除）、Agent 菜单、分享；侧栏的“新建对话”行删除（避免和 toolbar 重复），侧栏搜索保留在内容区。

## 7. 阶段

- **Phase 1（本阶段）**：主窗口原生 toolbar + 标题/副标题 + 按钮/菜单/搜索；示例与 Agent 迁移；删除页面标题条。设置窗口仍用原生标题栏 + Web 标签，页内菜单仍是 Web。
- **Phase 2**：设置窗口分类标签栏改原生（复用同一 item 工厂，加 `tabs`）；页内 `ContextMenu` 改原生 `NSMenu`（复用同一 menu 模型）。
- **不在 B 范围**：Composer、列表、Markdown、侧栏搜索等内容的原生控件。要做这些是 C 方向，需要另一次决策。

## 8. 验收

- 截图中主窗口 toolbar 是 `NSToolbar`，按钮有系统 bezel/hover/焦点，搜索框是 `NSSearchField`，菜单是 `NSMenu`。
- 页面不再出现自绘标题条；窗口标题/副标题只出现一次（原生 toolbar 里）。
- 示例：搜索过滤、排序菜单、新增按钮都工作；Agent：新建、⋯ 菜单、Agent 菜单、分享都工作。
- 深浅色各截一次示例和 Agent；toolbar 背景与侧栏/内容底色关系正确。
- 宿主不出现任何 app id / app 专属 Swift；只有通用 `NativeToolbarController`。
- `make lint`、`make test`、`make build`、`make release` 全过。
- 收尾报告必须列出：哪些是原生、哪些仍是 Web、Phase 2 未做的项、需人工确认的项。

## 9. 非目标

- 不引入第三方依赖。
- 不让 app 传样式或直接创建 AppKit 视图。
- 不把标题条/工具栏放回页面。
- 不在本阶段迁设置表单控件、页内菜单、Composer。
