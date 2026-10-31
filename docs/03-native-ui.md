# 03 · 原生界面规范

所有 app 的布局、按钮、菜单、设置都照 macOS 原生应用（手记、密码、备忘录、邮件）来做。插件只选语义组件，长什么样由壳决定；壳的实现优先用系统控件本身，不自己画。

判断标准：截图和同类系统 app 放一起看不出差别；深浅色、强调色、辅助功能、键盘操作全部自动跟随。

## 1. 窗口布局

窗口统一 `.titled + .fullSizeContentView`、unified 工具栏，红绿灯在左上，工具栏按钮是系统的玻璃胶囊（macOS 26+ 自动）。

### 1.1 两栏（参考手记，图 1）

```text
┌──────────┬─────────────────────────────────────────────┐
│ ●●●   [▥]│ [‹]  标题           [▢ ◎ ➤ ▮]     [格式 Ⓐ] (✓) │
│          │                                             │
│ 侧栏     │ 详情                                         │
└──────────┴─────────────────────────────────────────────┘
```

- `NavigationSplitView(sidebar:detail:)`，侧栏开关按钮由系统放在侧栏顶部，不自己做。
- 工具栏位置：`navigation`（返回）→ 标题 → `principal`（一组工具）→ `primaryAction`（右侧组）→ 最右一个 `prominent` 主按钮。
- 相邻按钮用 `ToolbarGroup` 合成一个胶囊，组之间用 `ToolbarSpacer` 分开。

### 1.2 三栏（参考密码，图 2）

```text
┌──────────┬──────────────────┬─────────────────────────┐
│ ●●●   [▥]│ 全部      [⇅ ＋]  │ [🔍 搜索              ]  │
│ 侧栏     │ 68 个项目          │                         │
│          │ 列表              │ 详情 / 空状态             │
└──────────┴──────────────────┴─────────────────────────┘
```

- `NavigationSplitView(sidebar:content:detail:)`。
- 中栏标题 + 副标题用 `navigationTitle` / `navigationSubtitle`；排序、新增按钮挂在中栏工具栏。
- 搜索用 `.searchable`，系统放在工具栏右侧。
- 没选中时详情区显示 `Empty`（`ContentUnavailableView`）：图标 + 标题 + 说明。

### 1.3 侧栏内容

- 普通侧栏：`List(.sidebar)` + `Section`，行 = 图标 + 标题 + 右侧计数，分组标题右侧可放一个 `+`。
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

- app 菜单的“设置…”只在 app 声明了 `<Settings>` 时出现；没有 key 窗口（只有浮窗）时菜单栏是 “Wisp Loom” 的壳菜单。
- app 命令在 TS 里用 `<Command menu="file" title="新建对话" shortcut="cmd+n" onAction={…}/>` 声明，同一个命令也可以放进工具栏。
- 风险：菜单栏粗体名称系统取进程名，可能始终显示 “Wisp Loom”，M1 实测后决定是否接受。

## 3. 设置窗口（图 4）

- `WindowFactory.makeSettingsWindow` 创建，内容是 `NSTabViewController(tabStyle: .toolbar)`：上方图标分类，窗口标题跟随当前分类，切换分类时窗口高度动画适配内容。
- 每个分类一个 `Form(.grouped)`：分组标题 + 圆角分组，行是开关 / 弹出菜单 / 文本框，说明文字用行内 `caption`。
- 每个 app 有自己的设置窗口，由 app 菜单的“设置… ⌘,”打开，在 TS 里声明：

```tsx
<Settings>
  <Pane id="general" title="通用" symbol="gearshape">
    <Section title="新对话">
      <Toggle title="自动生成标题" value={autoTitle} onChange={setAutoTitle} />
      <Picker title="默认 Agent" value={agent} options={agents} onChange={setAgent} />
    </Section>
  </Pane>
</Settings>
```

- 壳自己的设置（快捷键、语言、浮窗样式）也改成同样的结构。
- 需要“左边列表 + 右边表单”的分类（如模型服务商）用 `ListDetail`：左侧列表底部带 `+ / −`，和邮件的账户设置一样。

## 4. 组件清单

| 组件 | 原生实现 | 主要 props |
|---|---|---|
| `Window` | `NSWindow`（WindowFactory） | `title` `subtitle` |
| `Split` | `NavigationSplitView` | `columns`（2/3），`query` / `placeholder` / `onQuery`（有 `query` 才挂 `.searchable`），子节点 `Sidebar` / `Content` / `Detail`；每栏可带 `title` / `subtitle` 和自己的 `Toolbar` |
| `Toolbar` `ToolbarGroup` `ToolbarSpacer` | `.toolbar` / `ToolbarItemGroup` / `ToolbarSpacer` | `placement`（`principal` / `primaryAction`，默认右侧）；`Toolbar` 是所在容器（`Window` / `Content` 等）的子节点 |
| `Button` | `Button` | `title` `symbol` `role` `prominent` `shortcut` `disabled` `help` |
| `Menu` | `Menu` | `title` `symbol`，子节点 `Button` / `Divider` |
| `Command` | `NSMenuItem` | `menu` `title` `shortcut` |
| `List` `Section` `Row` | `List(selection:)` / `Section` / `Label` + `badge` | `selection` `onSelect`，`Row`：`value` `title` `subtitle` `symbol` `badge`（`contextMenu` 等有 app 用到再加） |
| `SidebarTiles` `Tile` | `LazyVGrid` + 系统材质 | `title` `symbol` `count` `tint` `onAction` |
| `Text` | `Text` | `style` `selectable` |
| `Markdown` | 壳内块级渲染（段落、标题、列表、代码块、表格、引用），行内用 `AttributedString(markdown:)` | `source`，支持 `append` |
| `TextField` `Toggle` `Picker` `SecureField` | 同名系统控件（`Stepper` 等有 app 用到再加） | `title` `value` `onChange`；`Picker` 另有 `options: [{value, title}]` |
| `Composer` | `TextEditor` + 两侧附件槽，系统圆角材质 | `placeholder` `value` `onSubmit` `submitKey`，子节点放左右按钮 |
| `Empty` | `ContentUnavailableView` | `title` `symbol` `description` |
| `Stack` `Spacer` `Divider` | `VStack` / `HStack` / `Spacer` / `Divider` | `axis`、间距只能是 `tight` / `regular` / `loose` 三档设计令牌 |
| `Scroll` | `ScrollView` + `LazyVStack` | `anchor="bottom"`（聊天） |
| `Sheet` `Alert` `Popover` | 同名系统修饰符 | `presented` `onDismiss` |
| `Settings` `Pane` | 见第 3 节；`Pane` 的子节点直接放进 `Form`（`Form` 不是独立组件） | `Pane`：`id` `title` `symbol` |
| `ListDetail` | 见第 3 节，M1 的模型设置用到时再加 | |

M0 已实现：`Window` `Split` `Toolbar` 系列 `Button` `Menu` `Command` `List` `Section` `Row` `SidebarTiles` `Tile` `Text` `Empty` `Stack` `Spacer` `Divider` `Settings` `Pane` `TextField` `SecureField` `Toggle` `Picker`。`Markdown` `Scroll` `Composer` `Sheet` `Alert` `Popover` `ListDetail` `Stepper` 等 M1 起随 Agent 加入，目前没有渲染实现。

新增组件的流程：先在这张表加一行 → `ShellCore` 的节点类型 → `ShellUI` 渲染 → `sdk/ts` 类型 → 测试。没有 app 用到的组件不加。

## 5. 性能要求

- 长列表必须 `Lazy`，消息列表只渲染可见区域。
- 流式输出只走 `append`，`Markdown` 只重新解析最后一个未闭合的块。
- 节点粒度 `@Observable`，一次 patch 只让受影响的节点重绘。
- 窗口关闭即释放该窗口的节点表；app 最后一个窗口关闭即释放 JSContext。
