# 04 · 第一个应用：Agent

模型对话应用。每次对话选一个 Agent（工具 + skill + 提示词的预设），可以自由切模型。后端对接不同服务商，统一成一套消息和事件。

## 1. 界面（参考图 5，样式按原生优先）

两栏布局，`Window columns={2}`：

```text
┌──────────────────────────────────────────────────────────────┐
│ ●●●   [新建]  对话标题 / Agent · Model   [⋯] [Agent ▾] [⇪] [🔍] │ ← 原生 NSToolbar
├───────────────┬──────────────────────────────────────────────┤
│ 对话           │  消息列表（Scroll anchor=bottom）               │
│  今天          │   用户消息：右侧气泡                            │
│  今天          │   助手消息：无气泡，全宽 Markdown                │
│   · 统计代码量  │   思考：可折叠的次要文本                         │
│  昨天          │   工具调用：可折叠行（M3 起）                     │
│   · …         │                                              │
│               │ ┌──────────────────────────────────────────┐ │
│               │ │ 发消息…                                   │ │
│               │ │ [+]                    [模型 ▾]      (↑)  │ │ ← Composer
│               │ └──────────────────────────────────────────┘ │
└───────────────┴──────────────────────────────────────────────┘
```

| 区域 | 内容 | 实现 |
|---|---|---|
| 窗口 toolbar | 左：侧栏折叠、新建对话；中间：窗口标题（当前对话）/ 副标题（Agent · Model）；右：`⋯` 菜单（重命名、复制为 Markdown、删除）、Agent 选择、分享、搜索 | `[Swift]` 原生 `NSToolbar`，页面用 `useToolbar` 声明；搜索是原生 `NSSearchField`；侧栏状态用 `useSidebar`；见 06 |
| 侧栏 | 对话列表按今天 / 昨天分组；右键：重命名、删除；不再放“新建对话”行（与 toolbar 重复） | `[TS]` `Sidebar` + `List` + `Section`；右键用 `ContextMenu`，宿主弹原生 `NSMenu` |
| 消息区 | 流式输出；生成中可以停止；每条助手消息悬停显示拷贝、重新生成 | `[TS]` `Scroll`（`anchor="bottom"`）+ `Markdown`，文本来自 `useStream` |
| 输入区 | 回车发送、⇧回车换行；左 `+`（附件，M3）；右模型选择（含思考强度）+ 发送/停止按钮 | `[TS]` `Composer` + `Menu` |
| 空状态 | 新对话：显示当前 Agent 名称和简介 | `[TS]` `Empty` |

**原生/Web 范围（Phase 1）：**

- 原生：窗口、红绿灯、标题栏、标题/副标题、toolbar 按钮/菜单/搜索/侧栏折叠、菜单栏。
- Web：侧栏列表、内容列表、消息/Markdown、Composer、设置表单。
- 原生：右键菜单、设置分类标签、对话搜索（toolbar 的 `NSSearchField`）。
- 内容组件只改 `ui/`；原生 toolbar 是宿主一次实现 + `useToolbar` 声明，不做 per-app Swift。

图 5 的“项目 / 任务”分组、“自主模式”、用户头像不进第一版。

本轮只搭界面骨架：`apps/agent` 没有 backend，数据是 `ui/mock.ts` 里的静态 mock；发送只在本地追加消息，并用 `useStream` 模拟逐字输出，不调用 `call()`。

设置窗口（app 菜单 → 设置… ⌘,）：

| 分类 | 内容 |
|---|---|
| 通用 `gearshape` | 默认 Agent、默认模型、自动生成标题、发送键 |
| 模型 `cpu` | `ListDetail`：左侧服务商列表 `+ / −`；右侧名称、协议、Base URL、API Key（`SecureField`）、模型列表（拉取 / 手动添加）、测试连接 |
| Agent `person.crop.square` | M2 补：名称、提示词、工具、skill |
| 工具 `wrench.and.screwdriver` / Skill `book` | M3 补 |

本轮只做通用与模型两个分类的表单骨架；模型分类里的 `ListDetail`（服务商列表）、拉取模型、测试连接要等 M1 后端。设置分类标签已由宿主原生 toolbar 渲染，app 仍只声明 `<Pane>` 列表。

## 2. 数据模型

参考 pi-mono `packages/ai` 的统一上下文设计，字段只取用得到的：

```text
Provider { id, name, api: "openai-completions" | "anthropic-messages" | "openai-responses" | "kiro",
           baseUrl, headers?, models: [Model] }        // API key 只在 Keychain：shell.secret "provider.<id>"
Model    { id, name, reasoning: bool, contextWindow, maxTokens }
Agent    { id, name, description, systemPrompt, tools: [toolId], skills: [skillId],
           defaults?: { model, thinking } }
Conversation { id, title, agentId, model: { provider, id, thinking }, created, updated }
Message  = User { content: [Text | Image] }
         | Assistant { content: [Text | Thinking | ToolCall], usage, stopReason, model, provider }
         | ToolResult { toolCallId, content, isError }
```

存储 `[Rust]`：`WISP_DATA_DIR` 下 `providers.json`、`agents.json`、`conversations/<id>.jsonl`（一行一条消息，只追加）。对话列表启动时只读每个文件的首行元信息。

## 3. 后端 `[Rust]`

`apps/agent/backend`，crate 依赖 `wisp-backend`、`serde`、`serde_json`、`ureq`，不用 async 运行时：每个请求一个线程，SSE 用阻塞按行读取。

### 3.1 模块

```text
src/main.rs          方法注册
src/store.rs         providers / agents / conversations 读写
src/sse.rs           按行解析 SSE（data: / event:），~40 行
src/provider/mod.rs  trait Provider { fn stream(&self, req, emit, cancelled) -> Result<Assistant> }
src/provider/openai_completions.rs
src/provider/anthropic.rs
src/provider/openai_responses.rs   M2
src/provider/kiro.rs               M2
src/agent_loop.rs    M3：工具调用循环
```

每个协议只做两件事：把统一上下文转成请求体，把流式响应转成统一事件。共用的部分（HTTP、SSE、取消、错误映射）只写一次。

### 3.2 统一事件

沿用 pi-ai 的事件形状，前端只认这一套：

```text
start
text_start / text_delta / text_end
thinking_start / thinking_delta / thinking_end
toolcall_start / toolcall_delta / toolcall_end      M3
done   { message: Assistant }
error  { code, message }
```

### 3.3 协议

| 协议 | 端点 | 要点 | 阶段 |
|---|---|---|---|
| OpenAI Chat Completions | `POST {base}/chat/completions`，`stream: true`，`stream_options.include_usage` | 覆盖 OpenAI 兼容服务（DeepSeek、GLM、Qwen、Ollama…）；`reasoning_content` / `reasoning` 字段映射到 thinking | M1 |
| Anthropic Messages | `POST {base}/v1/messages`，`x-api-key`、`anthropic-version` | `system` 单独字段；`content_block_start/delta/stop` 映射；`thinking.budget_tokens` 按思考强度换算 | M1 |
| OpenAI Responses | `POST {base}/responses` | `response.output_text.delta`、`response.reasoning_summary_text.delta` | M2 |
| Kiro | 待调研 | 鉴权方式、端点、事件格式先出调研文档再实现 | M2 |

### 3.4 方法

| 方法 | 说明 |
|---|---|
| `provider.list` / `provider.save` / `provider.delete` | 服务商配置，不含 key |
| `provider.models` | 拉取 `/models`（支持的协议才有） |
| `provider.test` | 发一条最小请求，返回耗时或错误 |
| `conversation.list` / `conversation.load` / `conversation.rename` / `conversation.delete` | 对话 |
| `chat.send { conversationId?, agentId, model, text }` | 追加用户消息并流式返回事件；结束后落盘；首轮结束后异步生成标题 |
| `chat.regenerate { conversationId, messageId }` | 从某条助手消息重新生成 |
| `cancel` | 停止生成，已生成的部分保留为 `stopReason: aborted` |
| `agent.list` / `agent.save` / `agent.delete` | M2 |

## 4. 前端 `[TS]`

```text
apps/agent/ui/
  main.tsx           Window、菜单命令、全局状态
  Sidebar.tsx        对话列表
  Chat.tsx           消息列表 + Composer
  Message.tsx        单条消息渲染
  Settings.tsx       设置窗口各分类
```

前端只持有界面状态（当前对话、输入框、正在生成的消息），数据都从后端取。流式事件写进 `useStream`，`Markdown` 渲染它的文本（每帧至多重渲染一次，只重新解析最后一个未闭合的块），`done` 后用完整消息替换。

## 5. 参考与极简原则

- 参考 [pi-mono](https://github.com/badlogic/pi-mono)：`packages/ai`（统一上下文、各协议的 provider、事件流）和 `packages/agent`（agent 循环、工具执行事件）。只借数据形状和协议映射，不照搬 TS 结构；开发前先读对应 provider 源码确认字段（本文写作时未能联网核对）。
- 不做：多模态输出、代理配置、token 计费、OAuth 登录（Kiro 如必须再议）。
- 后端目标代码量：M1 不超过 1500 行 Rust。
