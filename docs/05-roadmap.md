# 05 · 路线图

一个阶段一个或几个会话。每个任务标语言；每步完成都要过 `make build`、`make test`、`make lint` 和一次 Release 构建，界面任务还要和对应系统 app 截图对比。

## M0 · 平台底座（已完成）

代码、单测与构建已完成并通过 `make lint` / `make test` / `make build` / Release 构建。需要人工确认的：与系统 app 的截图对比（0.5、0.9）、菜单栏粗体名称（0.8）、全局快捷键、设置窗口切换分类时的高度动画。

| # | 任务 | 语言 | 完成标准 |
|---|---|---|---|
| 0.1 | `UITree` 节点表 + patch 应用（副本提交、rev 校验） | `[Swift]` ShellCore | 单测覆盖 6 种 op、旧 rev、失败回滚 |
| 0.2 | TS SDK：JSX 运行时、hooks、key diff、批量 commit、`call` | `[TS]` sdk/ts | `node --test` 覆盖 diff 输出的 op |
| 0.3 | `AppRuntime`：JSContext 线程、`__wisp` 注入、timer、console | `[Swift]` AppRuntime | 单测：脚本 commit 的 patch 到达 Swift |
| 0.4 | manifest 加载与多语言，替换 `AppDescriptor.samples` | `[Swift]` ShellCore + App | 启动器显示 `apps/` 下的 app |
| 0.5 | 原生渲染器第一批：Window、Split、Toolbar 系列、Button、Menu、List 系列、Text、Stack、Empty | `[Swift]` ShellUI | 示例 app 两栏 / 三栏截图对比手记、密码 |
| 0.6 | 后端通道：按需启动、JSON Lines、并发、取消、空闲退出、崩溃恢复 | `[Swift]` AppRuntime | 用假后端脚本跑通全部状态 |
| 0.7 | 后端 SDK | `[Rust]` sdk/rust、`[Py]` sdk/py | echo 示例 app 用两种语言各跑一次 |
| 0.8 | 菜单栏：regular / accessory 切换、按 key 窗口重建、`Command` | `[Swift]` ShellPlatform | 图 3 的菜单结构；实测菜单栏粗体名称 |
| 0.9 | 设置窗口框架：toolbar 分类、Form、Toggle / Picker / TextField / SecureField；壳设置迁过去 | `[Swift]` ShellUI + ShellPlatform | 截图对比图 4 |
| 0.10 | Keychain `shell.secret.*` | `[Swift]` AppRuntime | 单测；TS 读不到明文 |
| 0.11 | `make apps` 构建 + 开发期 FSEvents 热重载 | 构建脚本 + `[Swift]` | 改 tsx 后窗口内容替换、不重开 |

## M1 · Agent 能对话

| # | 任务 | 语言 |
|---|---|---|
| 1.1 | 存储：providers、conversations（jsonl） | `[Rust]` |
| 1.2 | SSE 解析 + Provider trait + 取消 | `[Rust]` |
| 1.3 | OpenAI Chat Completions | `[Rust]` |
| 1.4 | Anthropic Messages | `[Rust]` |
| 1.5 | `Markdown`、`Scroll`、`Composer` 组件 | `[Swift]` ShellUI |
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

参考 dsh 的轨迹视图和 dsh-context 插件：每轮请求的耗时、token、成本；上下文组成（系统提示、工具定义、历史、工具结果）占比；可以回看每次请求的原始请求体。统计 `[Rust]`，界面 `[TS]`，需要图表时再加原生 `Chart` 组件 `[Swift]`。开始前单独出设计文档。

## 暂不做

- Go：等出现需要独立打包、常驻的服务再定。
- 插件市场、git / 远程安装：先只支持本地目录。
- 签名与公证：拿到 Developer ID 后统一处理。

## M0 实现与文档的差异

- 0.2：`__wisp.call` 的签名是 `(method, params, onEvent, onDone)` 返回取消函数（JS 侧 `call()` 封装成 Promise + `abort()`）；`__wisp.lifecycle` 目前只有 `resync`；壳注入 `__wisp.rev` 作为热重载后的起始 rev。
- 0.4：manifest 的 `category` / `tint` / `window` 可省略；多语言“第一个”按键名排序。
- 0.5：`Split` 的搜索用 `query` / `onQuery` 属性，`Toolbar` 挂在所属容器下。
- 0.8：app 入口改为纯 AppKit `main.swift`（SwiftUI `App` 生命周期会覆盖主菜单）。
- 0.11：Rust 后端在仓库根的 cargo workspace 里，产物统一到 `build/cargo`；监听只在设置了 `WISP_APPS` 时启用。
