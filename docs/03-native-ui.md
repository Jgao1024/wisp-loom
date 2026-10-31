# 03 · 原生界面规范

所有 app 的布局、按钮、菜单、设置都照 macOS 原生应用（手记、密码、备忘录、邮件）来做。界面在 WKWebView 里由 TS 渲染，原生观感靠两件事保证：窗口、菜单、设置窗口由宿主用 AppKit 创建；页面只能用设计系统组件，样式表只用系统字体、系统颜色和少量间距令牌。

判断标准：截图和同类系统 app 放一起看不出差别；深浅色、强调色、辅助功能、键盘操作全部自动跟随。

## 1. 窗口布局

窗口统一 `.titled + .fullSizeContentView`，标题栏透明，红绿灯在左上。标题条和工具栏由页面（设计系统）绘制，按钮是设计系统的胶囊；窗口、菜单栏、设置窗口由宿主用 AppKit 创建。

### 1.1 两栏（参考手记，图 1）

```text
┌──────────┬─────────────────────────────────────────────┐
│ ●●●   [▥]│ [‹]  标题           [▢ ◎ ➤ ▮]     [格式 Ⓐ] (✓) │
│          │                                             │
│ 侧栏     │ 详情                                         │
└──────────┴─────────────────────────────────────────────┘
```

- `Window columns={2}`：侧栏 + 详情。窗口是 `.fullSizeContentView`，WebView 铺满整个窗口，背后是 `NSVisualEffectView(.sidebar)`；侧栏列不画背景，所以显示系统侧栏材质，内容列和详情列是不透明的 `Canvas`。
- 标题栏区域属于页面：每列顶部有一条可拖动的标题条（拖动、双击缩放由宿主执行），红绿灯落在侧栏顶部；侧栏没有标题时也保留同高度的空标题条，同样可拖动。
- 列的标题和工具栏用 `Content` / `Detail` 的 `title`、`subtitle`、`toolbar` 属性；相邻按钮用 `ToolbarGroup` 合成一个胶囊。

### 1.2 三栏（参考密码，图 2）

```text
┌──────────┬──────────────────┬─────────────────────────┐
│ ●●●   [▥]│ 全部      [⇅ ＋]  │ [🔍 搜索              ]  │
│ 侧栏     │ 68 个项目          │                         │
│          │ 列表              │ 详情 / 空状态             │
└──────────┴──────────────────┴─────────────────────────┘
```

- `Window columns={3}`：侧栏 + 内容列表 + 详情。
- 中栏标题 + 副标题；排序、新增按钮放在中栏的 `toolbar`。
- 搜索是详情列工具栏里的 `Search`。
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
- app 命令在 TS 里用 hook 声明：`useCommands([{ id: "new", menu: "file", title: "新建对话", shortcut: "cmd+n", run }])`。命令只是菜单项；同一个函数想放进工具栏，就另外绑一个 `Button`。
- 风险：菜单栏粗体名称系统取进程名，可能始终显示 “Wisp Loom”，M1 实测后决定是否接受。

## 3. 设置窗口（图 4）

- 壳自己的设置是 `NSTabViewController(tabStyle: .toolbar)`，每个分类里放一个 SwiftUI `Form(.grouped)`（`WindowFactory.makeSettingsWindow(panes:)`）。每个 app 的设置是同一个页面脚本在 `window: "settings"` 下渲染的 `<Settings>`：窗口顶部是 toolbar 风格的分类标签，窗口高度按当前分类内容动画调整。设置窗口不是侧栏材质：页面给 `body` 铺窗口背景（浅色时浅灰、卡片白；深色时深灰、卡片稍亮），分组标题在卡片外。
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
| `Window` | 整页布局 | `title` `subtitle` `columns`（2/3），子节点 `Sidebar` / `Content` / `Detail` |
| `Sidebar` `Content` `Detail` | 三种列 | `Content` / `Detail`：`title` `subtitle` `toolbar` |
| `ToolbarGroup` `Search` | 工具栏胶囊、搜索框 | `Search`：`value` `placeholder` `onInput` |
| `Button` `Menu` | 按钮、弹出菜单 | `title` `symbol` `role` `prominent` `disabled` `help` `onAction` |
| `List` `Section` `Row` | 列表（上下键选择） | `selection` `onSelect`；`Row`：`value` `title` `subtitle` `symbol` `badge` `selected` |
| `SidebarTiles` `Tile` | 卡片侧栏 | `title` `symbol` `count` `tint` `selected` `onAction` |
| `Text` `Stack` `Spacer` `Divider` `Empty` | 内容 | `Text`：`style` `selectable`；`Stack`：`axis` `spacing`（tight/regular/loose） |
| `Settings` `Pane` `Toggle` `Picker` `TextField` `SecureField` | 设置窗口 | `value` `placeholder` `onChange` |
| `useCommands` | 菜单栏命令（hook，不是组件） | `{id, menu, title, shortcut, run}` |

新增组件的流程：先在这张表加一行 → `ui/src/components.tsx` 和 `ui/src/style.css` → 示例或测试用到。没有 app 用到的组件不加；不需要改 Swift。`Markdown` `Scroll` `Composer` `Sheet` `Popover` `ListDetail` 等 M1 起随 Agent 加入。

## 5. 性能要求

- 长列表只渲染可见部分（超过几百行时才需要；先量再做）。
- 流式输出走 `useStream`，每帧至多重渲染一次。
- 窗口关闭即销毁 WebView；app 最后一个窗口关闭即释放会话和后端。
- 宿主不轮询：FSEvents 只在开发期开。
