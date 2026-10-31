# 03 · 原生界面规范

原生组件的登记、复用方式和“为什么侧栏不用 NSSplitView”见 `docs/07-native-components.md`。

所有 app 的布局、内容都照 macOS 原生应用（手记、密码、备忘录、邮件）来做。窗口级控件（标题栏、工具栏、菜单、设置分类标签）由宿主用 AppKit 原生实现；内容区在 WKWebView 里由 TS 渲染，只能用设计系统组件，样式表只用系统字体、系统颜色和少量间距令牌。完整契约见 `docs/06-native-toolbar.md`。

判断标准：窗口级控件必须是 `NSToolbar` / `NSButton` / `NSMenu` / `NSSearchField` 实例；内容区截图和同类系统 app 放一起看不出明显差别，深浅色、强调色、辅助功能跟随系统。

## 1. 窗口布局

窗口统一 `.titled + .fullSizeContentView`，标题栏透明，红绿灯在左上。标题栏和工具栏由宿主用 `NSToolbar` 原生创建并管理拖动/双击缩放；页面不再绘制标题条或 toolbar，内容列顶部留出 `--titlebar`（52pt）的原生 toolbar 高度。

### 1.1 两栏（参考手记，图 1）

```text
┌─────────────────────────────────────────────────────────┐
│ ●●●   [新建] [侧栏]   标题 / 副标题        [⋯] [Agent ▾] [⇪] │ ← 原生 NSToolbar
├──────────┬──────────────────────────────────────────────┤
│ 侧栏     │ 详情 / 内容                                   │
└──────────┴──────────────────────────────────────────────┘
```

- `Window columns={2}`：侧栏 + 详情。窗口是 `.fullSizeContentView`，WebView 铺满整个窗口，背后是 `NSVisualEffectView(.sidebar)`；侧栏列不画背景，所以显示系统侧栏材质，内容列和详情列是不透明的 `Canvas`，一直铺到窗口顶，原生 toolbar 透明地盖在上面。侧栏折叠时 `Window sidebar={false}` 给根节点加 `sidebar-hidden`，列直接移出布局，详情占满。
- 窗口标题/副标题由 `Window title/subtitle` 设置，显示在原生 toolbar 里；页面不再有列标题条。
- 工具栏用 `useToolbar(spec, handlers, onSearch?)` 声明；按钮、菜单、搜索、侧栏折叠都是原生控件。红绿灯、拖动、双击缩放全由宿主处理。侧栏折叠按钮是 `{ id, sidebar: true }` item，点击后页面用 `useSidebar` 切换 `Window sidebar`。

### 1.2 三栏（参考密码，图 2）

```text
┌─────────────────────────────────────────────────────────┐
│ ●●●   [新建]           全部 / 68 个项目      [⇅] [＋] [🔍] │ ← 原生 NSToolbar
├──────────┬──────────────────┬─────────────────────────┤
│ 侧栏     │ 列表              │ 详情 / 空状态             │
└──────────┴──────────────────┴─────────────────────────┘
```

- `Window columns={3}`：侧栏 + 内容列表 + 详情。
- 分组名/项目数用 `Window title/subtitle`，显示在原生 toolbar；排序、新增、搜索都进原生 toolbar（`useToolbar`），不再放在中栏里。
- 没选中时详情区显示 `Empty`：图标 + 标题 + 说明。

### 1.3 侧栏内容

- 普通侧栏：`List` + `Section`，行 = 图标 + 标题 + 右侧计数。列表支持上下键移动选择。
- 卡片侧栏（图 1、图 2 顶部的彩色卡片）：`SidebarTiles`，两列网格，每块 = 图标 + 计数 + 标题 + `tint`。颜色只能用 `tint` 枚举。

## 2. 菜单栏（图 3）

- 没有 app 窗口时保持 `.accessory`（不出现在 Dock 和菜单栏）。有 app 窗口成为 key 时切 `.regular`，所有 app 窗口关闭后切回。
- 菜单栏按“当前 key 窗口属于哪个 app”重建，壳提供固定骨架，app 只能往里加项：

| 菜单 | 内容 | 来源 |
|---|---|---|
| app 菜单 | 关于 X / 设置… ⌘, / 服务 / 隐藏 X ⌘H / 隐藏其他 ⌥⌘H / 全部显示 / 退出 X ⌘Q | 壳；“退出”只关这个 app 的窗口，不退出 Wisp Loom |
| 文件 | app 声明的命令（如新建对话 ⌘N）+ 关闭窗口 ⌘W | app + 壳 |
| 编辑 | 撤销、剪切、拷贝、粘贴、全选、查找 | 壳，走响应链 |
| 显示 | 显示/隐藏侧栏 ⌃⌘S、进入全屏 + app 命令 | 壳 + app |
| 窗口 / 帮助 | 系统标准 | 壳 |

- app 菜单的“设置…”只在 manifest 里 `settings: true` 时出现；没有 key 窗口（只有浮窗）时菜单栏是 “Wisp Loom” 的壳菜单。
- app 命令在 TS 里用 hook 声明：`useCommands([{ id: "new", menu: "file", title: "新建对话", shortcut: "cmd+n", run }])`。命令只是菜单项；同一个函数想放进原生 toolbar，就在 `useToolbar` 的 handlers 里绑同一个函数。
- 风险：菜单栏粗体名称系统取进程名，可能始终显示 “Wisp Loom”，M1 实测后决定是否接受。

## 3. 设置窗口（图 4）

- 壳自己的设置是 `NSTabViewController(tabStyle: .toolbar)`，每个分类里放一个 SwiftUI `Form(.grouped)`（`WindowFactory.makeSettingsWindow(panes:)`）。每个 app 的设置是同一个页面脚本在 `window: "settings"` 下渲染的 `<Settings>`：窗口顶部是原生分类标签（`.preference` toolbar 样式：标题栏一行、标签栏一行），窗口高度按当前分类内容动画调整。设置窗口不是侧栏材质：页面给 `body` 铺窗口背景（浅色时浅灰、卡片白；深色时深灰、卡片稍亮），分组标题在卡片外。
- app 设置分类标签已用原生 `NSToolbarItem`（SF Symbol + 标题）和 `NSToolbar.selectedItemIdentifier`，复用同一套 toolbar item 工厂（见 06/07）；表单控件仍在 Web。
- 每个分类一个 `Pane`，里面是 `Section` 分组的 `Toggle` / `Picker` / `TextField` / `SecureField`；改动立即写入 app 设置并广播给同 app 的其他窗口。
- 由 app 菜单的“设置… ⌘,”打开，manifest 里 `settings: true` 才有。

```tsx
run(<Main />, (
  <Settings>
    <Pane id="general" title="General" symbol="gearshape">
      <Section title="Window">
        <Toggle title="Show group" value={show} onChange={setShow} />
      </Section>
    </Pane>
  </Settings>
))
```

- `ListDetail`（左边列表 + 右边表单，用于 M1 的模型服务商）等有 app 用到再加。

## 4. 组件清单

页面组件都在 `ui/src/components.tsx`，样式只在 `style.css`。

| 组件 | 说明 | 主要 props |
|---|---|---|
| `Window` | 整页布局；标题/副标题进原生 toolbar | `title` `subtitle` `columns`（2/3）`sidebar`，子节点 `Sidebar` / `Content` / `Detail` |
| `Sidebar` `Content` `Detail` | 三种内容列，不再有标题/工具栏 | 只有子节点 |
| `useToolbar` | 原生 toolbar 声明（hook，不是组件） | `spec` `handlers` `onSearch`；见 06 |
| `useSidebar` | 侧栏显示状态 + 切换函数（hook） | `initial`；结果接 `Window sidebar` 和 `sidebar` toolbar item |
| `Search` | 内容区搜索框（Agent 侧栏用） | `value` `placeholder` `onInput` |
| `Button` `Menu` | 内容区按钮、弹出菜单（不用于窗口 toolbar） | `title` `symbol` `role` `prominent` `disabled` `help` `onAction` |
| `List` `Section` `Row` | 列表（上下键选择） | `selection` `onSelect`；`Row`：`value` `title` `subtitle` `symbol` `badge` `selected` |
| `SidebarTiles` `Tile` | 卡片侧栏 | `title` `symbol` `count` `tint` `selected` `onAction` |
| `Text` `Stack` `Spacer` `Divider` `Empty` | 内容 | `Text`：`style` `selectable`；`Stack`：`axis` `spacing`（tight/regular/loose） |
| `Settings` `Pane` `Toggle` `Picker` `TextField` `SecureField` | 设置窗口 | `value` `placeholder` `onChange` |
| `Scroll` | 可滚动区域；`anchor="bottom"` 时贴底（消息流） | `anchor` |
| `Markdown` | 消息正文：段落、标题、列表、代码块、行内代码、引用（表格后置） | `text` |
| `Composer` | 输入区：回车发送、⇧回车换行，发送后清空；`busy` 时变停止 | `value` `placeholder` `onChange` `onSend` `busy` `onStop` `sendWith` |
| `ContextMenu` | 右键菜单，由宿主弹原生 `NSMenu`；`items` 为 `{id, title, onAction, destructive?, disabled?}` | `items` |
| `useCommands` | 菜单栏命令（hook，不是组件） | `{id, menu, title, shortcut, run}` |

新增组件的流程：先在这张表加一行 → `ui/src/components.tsx` 和 `ui/src/style.css` → 示例或测试用到。没有 app 用到的组件不加；内容组件不需要改 Swift，新增原生控件类型才改宿主一次。`Sheet` `Popover` `ListDetail` 等随后续 Agent 阶段加入。

## 5. 性能要求

- 长列表只渲染可见部分（超过几百行时才需要；先量再做）。
- 流式输出走 `useStream`，每帧至多重渲染一次。
- 窗口关闭即销毁 WebView；app 最后一个窗口关闭即释放会话和后端。
- 宿主不轮询：FSEvents 只在开发期开。
