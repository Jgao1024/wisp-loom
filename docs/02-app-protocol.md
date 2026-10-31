# 02 · 应用插件协议

一个 app = 一个目录：manifest + TS 界面 + 可选后端。本文定义三条边界：manifest、界面桥（TS ↔ Swift）、后端通道（Swift ↔ 后端进程）。

## 1. manifest.json

```json
{
  "id": "dev.wisp.agent",
  "name": { "zh-Hans": "Agent", "en": "Agent" },
  "category": { "zh-Hans": "效率", "en": "Productivity" },
  "symbol": "sparkles",
  "tint": "purple",
  "ui": "ui.js",
  "settings": true,
  "backend": { "exec": ["backend/agent"], "idle": 120 },
  "window": { "size": [1100, 720], "min": [720, 480] }
}
```

- `backend` 可选。`exec` 是相对 app 目录的命令数组，Python 写成 `["python3", "backend/main.py"]`。`idle` 是无请求多少秒后退出，`0` 表示常驻。
- 文本字段都可以是字符串或多语言表，回落顺序：当前语言 → `en` → 第一个（JSON 对象无序，按键名排序取第一个）。
- `settings` 可选，为 `true` 时 app 菜单出现「设置… ⌘,」，打开同一页面的设置窗口。
- manifest 替代原来的 `AppDescriptor.samples`（已删除）。`category`、`tint`、`window` 可省略，默认分类为空、`accent`、900×600（最小 480×320）。

## 2. 页面桥 `[TS]` ↔ `[Swift]`

### 2.1 运行方式

- 每个 app 窗口一个 `WKWebView`，加载 `wisp://app/index.html`。宿主合成这个入口页，引用 manifest 里 `ui` 指向的脚本和同名 `.css`；其余文件从 app 目录读取（路径不能越出目录）。不给 WebKit 文件访问权限。
- 页面里的链接不在窗口内跳转，一律交给默认浏览器。
- 同一个 app 的窗口共享一个会话（后端、命令）；最后一个窗口关闭，会话和后端一起释放，WebView 随窗口销毁。
- 设置窗口加载同一个脚本，`boot.window === "settings"`，由 `run(app, settings)` 选择渲染哪个页面。

### 2.2 消息

页面 → 宿主：`window.webkit.messageHandlers.wisp.postMessage(json)`，一条一个 JSON：

| `type` | 字段 | 说明 |
|---|---|---|
| `call` | `id` `method` `params` | 调后端；`method` 以 `shell.` 开头则由宿主处理 |
| `cancel` | `id` | 取消一个进行中的 `call` |
| `setting` / `setSetting` | `id` `key` / `key` `value` | 读写 app 设置（UserDefaults，按 app id 隔离）；写入后广播给同 app 的其他窗口 |
| `commands` | `commands[]` | 注册菜单栏命令 `{id, menu, title, shortcut?, disabled?}` |
| `toolbar` | `spec` | 设置/更新本窗口的原生 toolbar；结构见 `docs/06-native-toolbar.md` |
| `title` / `height` | | 窗口标题/副标题、设置窗口高度（原生 toolbar 显示标题） |
| `openSettings` / `log` | | 打开 app 设置窗口、写宿主日志 |

宿主 → 页面：`window.__wisp_recv([...])`，同一轮事件循环里的消息合成一个数组、一次 `evaluateJavaScript`：

| `type` | 字段 | 说明 |
|---|---|---|
| `reply` | `id` + `event` / `result` / `error` | `call` 的流式事件和结局；`setting` 的结果 |
| `command` | `id` | 菜单命令被触发 |
| `toolbarAction` | `id` | 原生 toolbar 按钮/菜单项被点击 |
| `toolbarSearch` | `text` | 原生搜索框文本变化 |
| `settingChanged` | `key` `value` | 其他窗口改了设置 |

启动参数：`window.__wisp_boot = {appID, lang, title, hasBackend, window}`，在任何脚本之前注入。

### 2.3 TS SDK `ui/`

Preact 渲染 DOM，不再有自己的 reconciler 和 patch 协议。SDK 提供：

- 设计系统组件和样式表（见 03）；
- hooks：Preact 全套，加 `usePersisted`（设置）、`useStream`（流式文本，每帧至多重渲染一次）、`useCommands`（菜单命令）、`useToolbar`（原生 toolbar 声明）、`useSidebar`（侧栏显示状态）；
- 桥：`call(method, params, {onEvent})` 返回带 `abort()` 的 Promise，`setting` / `setSetting` / `setSecret` / `deleteSecret`，`registerCommands`，`registerToolbar`；
- `run(app, settings?)` 把页面挂到 `document.body`。
- 窗口 toolbar 的侧栏折叠 item 带 `sidebar: true`，点击仍回传 `{type:"toolbarAction", id}`；页面把 `useSidebar` 的 toggle 绑到该 id，并用 `Window sidebar` 切列。

页面里可以直接用 `fetch` 等 Web API，但网络与计算密集的工作建议放后端：后端进程可以脱离窗口存活、能被取消、能读 Keychain。

### 2.4 受控输入

内容区的页面就是原生 DOM，文本框输入立即显示，不需要往返宿主。窗口 toolbar 的搜索框是原生 `NSSearchField`，文本经 `toolbarSearch` 回传页面；页面不要回写搜索值，避免重建 toolbar。

### 2.5 组件只讲语义

插件不能传颜色、字体、尺寸、边距：组件不接受 `style` / `class`，只有 `prominent` / `role`、文本 `style`（`title` / `headline` / `body` / `caption` / `secondary`）、SF Symbol 名称、`tint` 枚举。SF Symbol 由宿主渲染成模板图经 `wisp://app/__symbol/<name>.png` 提供，页面用 CSS mask 着色。

窗口级控件同样只讲语义：toolbar 的 `ToolbarSpec` 只有 id、SF Symbol、标题、菜单项、搜索占位、侧栏折叠和禁用，宿主决定 `NSToolbarItem` / `NSMenuToolbarItem` / `NSSearchToolbarItem` 的样子。页面不再画标题条/工具栏，也不再发送 `drag` / `zoom`。

## 2.6 原生 toolbar

Phase 1 的完整契约见 `docs/06-native-toolbar.md`：宿主一个通用 `NativeToolbarController`，页面用 `useToolbar(spec, handlers, onSearch?)` 声明；每个 app 只写 item 和 handler，不写 Swift/CSS。设置窗口标签栏、页内 `ContextMenu` 是 Phase 2，仍走 Web。

## 3. 后端通道 `[Swift]` ↔ `[Rust]` / `[Py]` / `[Go]`

### 3.1 传输

- 子进程 stdin / stdout，每行一个 JSON（JSON Lines），UTF-8。stderr 进壳的日志。
- 环境变量：`WISP_APP_ID`、`WISP_DATA_DIR`（`~/Library/Application Support/WispLoom/Data/<id>/`）、`WISP_LANG`。
- 首个 `call` 时启动；`idle` 秒内没有请求、也没有进行中的请求就关闭 stdin，后端应自行退出，2 秒后仍在则 SIGTERM。
- 崩溃：进行中的请求全部以 `backend_crashed` 失败，下次 `call` 重启。连续 3 次启动即崩溃则暂停并在界面报错。

### 3.2 消息

```jsonc
// 请求（壳 → 后端）
{"id": 7, "method": "chat.send", "params": {}}
// 流式事件（后端 → 壳，可多条）
{"id": 7, "event": {"type": "text_delta", "delta": "你"}}
// 结束（二选一）
{"id": 7, "result": {}}
{"id": 7, "error": {"code": "http_401", "message": "API key 无效"}}
// 取消（壳 → 后端）
{"method": "cancel", "params": {"id": 7}}
// 后端调用壳能力（id 用字符串，和壳的数字 id 不冲突）
{"id": "s1", "method": "shell.secret.get", "params": {"key": "provider.openai"}}
```

- 后端必须支持并发请求（Rust SDK 每个请求一个线程），取消后尽快发 `error: cancelled`。
- 事件不做背压；SDK 在后端侧按 16ms 合并同类 `*_delta`，避免高频小包。

### 3.3 壳能力

后端和 TS 都通过 `call` 访问，方法名以 `shell.` 开头，按 app id 隔离：

| 方法 | 谁能调 | 说明 |
|---|---|---|
| `shell.secret.get/set/delete` | 后端；TS 只能 `set`/`delete` | Keychain，TS 永远读不到明文 |
| `shell.notify` | 两者 | 系统通知 |
| `shell.openPanel` / `shell.savePanel` | TS | 文件选择，返回路径 |
| `shell.openURL` | TS | 用默认浏览器打开 |

只在有 app 用到时才加新能力，加之前先更新这张表。

### 3.4 SDK

- `backend/rust`（crate `wisp-backend`）：读行、分发到 `fn(params, ctx) -> Result<Value>`，`ctx.emit(event)`、`ctx.cancelled()`、`ctx.shell(method, params)`。依赖只有 `serde` / `serde_json`。
- `backend/py`：单文件，同样的接口，只用标准库。
- Go 等到第一个确实需要的 app 再写。

## 4. 热重载（仅开发期）

- 只在设置了 `WISP_APPS` 时才创建 FSEvents 监听（监听该目录，200ms 去抖，不轮询）；发布版不开。
- `ui.js` / `ui.css` 变了：该 app 所有窗口的 WebView `reload()`，窗口不关，界面状态清零。
- 后端可执行文件变了：等进行中的请求结束后重启后端。
- `manifest.json` 变了：重新扫描目录并刷新启动器（新增、删除、改名都生效），已开窗口不动。
- 截图：`WISP_OPEN=<appID>` 启动后直接打开该 app 的主窗口（加 `WISP_OPEN_SETTINGS=1` 则打开设置窗口），不经过浮窗；只在 Debug 构建里读，发布版没有这段代码。`scripts/shot.sh` 用它在一条命令里完成“启动 → 按 owner 找窗口 → `screencapture -l` → 退出”，图存到 `build/shots/`。
