# 05 · 路线图

一个阶段一个或几个会话。每个任务标语言；每步完成都要过 `make build`、`make test`、`make lint` 和一次 Release 构建，界面任务还要和对应系统 app 截图对比。

## M0 · 平台底座（已完成，按 Raycast 2.0 的四层重做）

代码、单测与构建已完成。需要人工确认的：与系统 app 的截图对比（三栏窗口、设置窗口）、菜单栏粗体名称、全局快捷键、设置窗口切换分类时的高度动画、侧栏材质穿透效果、`make dev` 的端到端热重载。

| # | 任务 | 语言 | 状态 |
|---|---|---|---|
| 0.1 | manifest 解码与多语言回落，替换 `AppDescriptor.samples` | `[Swift]` ShellCore | 完成，有单测 |
| 0.2 | TS SDK：Preact + 设计系统组件 + 桥（`call` / 设置 / 命令 / 流式） | `[TS]` ui/ | 完成，`node --test` 覆盖桥协议 |
| 0.3 | `AppSession`：每窗口一条连接、后端共享、命令、设置广播 | `[Swift]` AppRuntime | 完成，有单测 |
| 0.4 | WKWebView 承载：`wisp://` scheme、message handler、SF Symbol 路由、窗口请求 | `[Swift]` ShellUI | 完成 |
| 0.5 | 后端通道：按需启动、JSON Lines、并发、取消、空闲退出、崩溃恢复 | `[Swift]` AppRuntime | 完成，假后端脚本跑通全部状态 |
| 0.6 | 后端 SDK | `[Rust]` backend/rust、`[Py]` backend/py | 完成，各有测试 |
| 0.7 | 菜单栏：regular / accessory 切换、按 key 窗口重建、命令 | `[Swift]` ShellPlatform | 完成，需人工确认 |
| 0.8 | 设置窗口：app 设置是同页面的 `<Settings>`；壳设置用 toolbar 标签 | `[TS]` + `[Swift]` | 完成，需人工确认 |
| 0.9 | Keychain `shell.secret.*` | `[Swift]` AppRuntime | 完成，页面读不到明文 |
| 0.10 | `make apps` 构建 + 开发期 FSEvents 热重载 | 构建脚本 + `[Swift]` | 完成 |

### 为什么从原生渲染改成 WKWebView

M0 的第一版是“JSContext + patch 协议 + SwiftUI 节点渲染器”（对应 Raycast v1 的做法）。读了 Raycast 官方文章和 8 个大型插件的源码后改掉：

- Raycast v1 的插件只能选宿主预设的页面模板（List / Detail / Form / Grid），所以不改宿主；我们要自己做很多界面各异的应用，每种新布局都要改 Swift，不可持续。
- Raycast 2.0 的界面全部在 Web 前端，Swift 宿主只管窗口、热键、菜单栏和进程监管；我们照这个分层。
- JSContext 里没有 `fetch` 等 Web API，放开能力要自己逐个实现；WebView 自带。

### 内存与耗时实测（M0 小验证）

5000 行列表，Preact 渲染，WKWebView（Debug 单窗口，Apple Silicon）：

| | 数值 |
|---|---|
| JS 渲染 5000 行 | 约 50–65 ms |
| 窗口出现到首帧（含 WebContent 进程启动） | 约 200–300 ms；空页面约 160 ms |
| WebContent 常驻内存 | 约 93 MB（空页面约 24 MB） |
| 壳进程 | 约 87 MB（验证程序，未含 M0 的其余代码） |

因此：长列表在几千行量级可以先整表渲染；窗口首次打开有进程启动成本（约 100–150 ms），如果后续觉得慢，可以预热一个空 WebView。这些数字只是量级，没有和 SwiftUI 版本做同条件对比。

### 与文档的差异

- 页面桥是 `window.webkit.messageHandlers.wisp` 加 `window.__wisp_recv`，不再有 `__wisp` 全局、JSContext、`UITree` 和 patch 协议。
- app 的 `ui.css` 与 `ui.js` 同名同目录，由宿主合成的入口页引用。
- manifest 增加可选的 `settings` 布尔值。
- app 入口改为纯 AppKit `main.swift`（SwiftUI `App` 生命周期会覆盖主菜单）。
- Rust 后端在仓库根的 cargo workspace 里，产物统一到 `build/cargo`；FSEvents 监听只在设置了 `WISP_APPS` 时启用。
- 设置窗口在页面里自己报告内容高度，宿主据此调整窗口高度（保持顶边不动）。

## M1 · Agent 能对话

| # | 任务 | 语言 |
|---|---|---|
| 1.1 | 存储：providers、conversations（jsonl） | `[Rust]` |
| 1.2 | SSE 解析 + Provider trait + 取消 | `[Rust]` |
| 1.3 | OpenAI Chat Completions | `[Rust]` |
| 1.4 | Anthropic Messages | `[Rust]` |
| 1.5 | `Markdown`、`Scroll`、`Composer`、`ContextMenu` 组件（`Markdown` 只重新解析最后一个未闭合的块） | `[TS]` ui/ |
| 1.6 | 侧栏、消息区、Composer、模型选择、停止生成 | `[TS]` |
| 1.7 | 设置：通用、模型（ListDetail、拉取模型、测试连接） | `[TS]` |
| 1.8 | 自动生成标题、导出 Markdown | `[Rust]` + `[TS]` |

完成标准：两种协议各对接一个真实服务商对话成功，流式输出不卡顿，取消立即生效；内置一个默认 Agent（只有提示词）。

## M2 · 协议补齐与 Agent 配置

| # | 任务 | 语言 |
|---|---|---|
| 2.1 | OpenAI Responses | `[Rust]` |
| 2.2 | Kiro：先出调研文档（鉴权、端点、事件），再实现 | `[Rust]` |
| 2.3 | Agent 预设：增删改、对话时选择、默认模型 | `[Rust]` + `[TS]` |

## M3 · 工具与 Skill

| # | 任务 | 语言 |
|---|---|---|
| 3.1 | agent 循环：工具调用 → 执行 → 回填，`toolcall_*` 事件 | `[Rust]` |
| 3.2 | 工具管理：内置工具（读文件、执行命令，带确认）、启用开关 | `[Rust]` + `[TS]` |
| 3.3 | Skill 管理：目录导入、按 Agent 挂载 | `[Rust]` + `[TS]` |
| 3.4 | 消息区工具调用折叠行、执行确认 Sheet | `[TS]` |
| 3.5 | 附件（图片、文件） | `[Swift]` 文件选择 + `[Rust]` + `[TS]` |

## M4 · 监控与上下文洞察

参考 dsh 的轨迹视图和 dsh-context 插件：每轮请求的耗时、token、成本；上下文组成（系统提示、工具定义、历史、工具结果）占比；可以回看每次请求的原始请求体。统计 `[Rust]`，界面 `[TS]`，需要图表时在 `ui/` 加 `Chart` 组件 `[TS]`。开始前单独出设计文档。

## 暂不做

- Go：等出现需要独立打包、常驻的服务再定。
- 插件市场、git / 远程安装：先只支持本地目录。
- 签名与公证：拿到 Developer ID 后统一处理。
