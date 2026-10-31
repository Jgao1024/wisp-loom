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
  "backend": { "exec": ["backend/agent"], "idle": 120 },
  "window": { "size": [1100, 720], "min": [720, 480] }
}
```

- `backend` 可选。`exec` 是相对 app 目录的命令数组，Python 写成 `["python3", "backend/main.py"]`。`idle` 是无请求多少秒后退出，`0` 表示常驻。
- 文本字段都可以是字符串或多语言表，回落顺序：当前语言 → `en` → 第一个（JSON 对象无序，按键名排序取第一个）。
- manifest 替代原来的 `AppDescriptor.samples`（已删除）。`category`、`tint`、`window` 可省略，默认分类为空、`accent`、900×600（最小 480×320）。

## 2. 界面桥 `[TS]` ↔ `[Swift]`

### 2.1 运行方式

- 每个运行中的 app 一个 `JSContext`，跑在专属串行线程。第一个窗口打开时创建，最后一个窗口关闭后销毁。
- 壳注入一个全局对象 `__wisp`，SDK 之外的代码不直接用它：

| 方向 | 接口 | 用途 |
|---|---|---|
| TS → Swift | `__wisp.commit(json)` | 提交一批界面 patch |
| TS → Swift | `__wisp.call(method, params, onEvent, onDone)` → 取消函数 | 调后端或壳能力；参数和结果都是 JSON 字符串，SDK 的 `call()` 把它包成 Promise + `abort()` |
| TS → Swift | `__wisp.setting(key)` / `__wisp.setSetting(key, value)` | 读写 app 设置（壳存在 UserDefaults，按 app id 隔离） |
| TS → Swift | `setTimeout` / `clearTimeout` / `console` | 壳实现，JSC 默认没有 |
| Swift → TS | `__wisp.dispatch(handler, value)` | 用户交互事件 |
| Swift → TS | `__wisp.lifecycle(kind)` | M0 只有 `resync`：壳拒绝了某个 patch，要求 JS 重发全量 `replace`。其余（语言、深浅色）等有 app 用到再加 |
| 壳 → TS | `__wisp.rev` | 注入的起始 rev，热重载后 JS 从这里继续递增 |

### 2.2 TS SDK `sdk/ts`

零运行期依赖，自己实现一个小型 reconciler：函数组件 + `useState` / `useEffect` / `useMemo` / `useRef` + `key` 驱动的同层复用。

- 状态变化不立即渲染，同一事件循环内合并，一次 `commit`。
- 流式内容（模型输出）用 `useStream`：不进 diff，直接发 `append` op。
- 后端调用：`call(method, params, { onEvent })`，返回 Promise，可 `abort()`。

### 2.3 界面树与 patch

节点：`{ id, type, props, children }`，`id` 由 SDK 分配并保持稳定（有 `key` 按 key，否则按位置）。事件 prop 的值是 handler id，函数本身留在 JS。

```json
{ "rev": 42, "ops": [
  { "op": "replace", "node": { "id": "r", "type": "Window", "props": {}, "children": [] } },
  { "op": "insert", "parent": "n3", "index": 2, "node": { } },
  { "op": "remove", "id": "n9" },
  { "op": "move", "id": "n7", "parent": "n3", "index": 0 },
  { "op": "update", "id": "n5", "props": { "title": "新标题" } },
  { "op": "append", "id": "n12", "prop": "text", "value": "增量文本" }
] }
```

- `rev` 由 JS 运行时单调递增，热重载也不归零；Swift 丢弃旧 rev。
- Swift 侧 `ShellCore.UITree` 先在副本上应用整批 op，全部成功才提交，失败则请求一次全量 `replace`。
- 每个节点是一个 `@Observable` 对象，SwiftUI 只重绘 props 变了的节点，长列表和流式输出不触发整树重算。

### 2.4 受控输入

文本框的输入内容以原生为准：用户输入立即显示，`onChange` 合并后再发给 TS（合并窗口 1 帧）。TS 回写的 `value` 只有跟原生当前值不同才会覆盖（例如发送后清空）。这样输入不受跨线程往返影响。

### 2.5 组件只讲语义

插件不能传颜色、字体、尺寸、边距。允许的变体只有系统本身就有的语义：按钮 `prominent` / `role`、文本 `style`（`title` / `headline` / `body` / `caption` / `secondary`）、SF Symbol 名称、`tint` 枚举。组件清单和对应的原生控件见 `03-native-ui.md`。

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

- `sdk/rust`（crate `wisp-backend`）：读行、分发到 `fn(params, ctx) -> Result<Value>`，`ctx.emit(event)`、`ctx.cancelled()`、`ctx.shell(method, params)`。依赖只有 `serde` / `serde_json`。
- `sdk/py`：单文件，同样的接口，只用标准库。
- Go 等到第一个确实需要的 app 再写。

## 4. 热重载（仅开发期）

- 只在设置了 `WISP_APPS` 时才创建 FSEvents 监听（监听该目录，200ms 去抖，不轮询）；发布版不开。
- `ui.js` 变了：重建 JSContext，`rev` 接着加，发全量 `replace`；窗口不关，界面状态清零。
- 后端可执行文件变了：等进行中的请求结束后重启后端。
- `manifest.json` 变了：重新扫描目录并刷新启动器（新增、删除、改名都生效），已开窗口不动。
