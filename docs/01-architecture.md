# 01 · 架构与语言分工

Wisp Loom 从启动器扩展成“原生 app 平台”：每个 app 是一个插件目录，TS 写界面，Rust（必要时 Python / Go）写后端，界面一律由壳用原生组件渲染。

## 1. 硬约束

1. 观感是原生的，样式由壳统一决定：插件只描述语义（窗口、分栏、列表、表单、按钮），不能传颜色、字号、边距、尺寸。字体、颜色、深浅色、强调色一律走系统令牌。
2. 新应用、新布局不改 Swift：界面全部在 TS（页面）里组合，Swift 只管宿主。
3. 性能好、占用低：后端按需启动、空闲退出，壳空闲时不轮询，窗口关闭即释放页面。
4. 壳零第三方依赖；TS SDK 只依赖 Preact；插件后端见第 5 节。

## 2. 进程模型（参考 Raycast 2.0 的四层）

```text
Wisp Loom.app（一个 Swift 进程）
 ├─ 宿主：窗口、菜单栏、状态栏、热键、Keychain、WKWebView 承载、后端监管   [Swift]
 ├─ 页面：每个 app 窗口一个 WKWebView（独立 WebContent 进程）              [TS + Preact]
 │    经自定义 scheme wisp://app/ 读取 app 目录，经一个 message handler 与宿主通信
 └─ 后端子进程：每个 app 至多一个，按需启动                                [Rust / Python / Go]
      stdin/stdout · JSON Lines
```

| 层 | 职责 | 不负责 |
|---|---|---|
| 宿主 `[Swift]` | 窗口、菜单、系统能力、后端进程、Keychain、设置存储 | 任何 app 的界面和业务 |
| 页面 `[TS]` | 所有界面：布局、列表、表单、交互、设计系统组件 | 网络之外的系统能力（经宿主） |
| 后端 `[Rust]` | 网络、协议、存储、计算 | 界面 |
| 后端 `[Py]` / `[Go]` | 必须用对应生态的部分 | 常驻、高频的服务 |

为什么这样分：

| 选择 | 理由 |
|---|---|
| 页面用 WKWebView | 系统自带，不打包浏览器内核；有完整的 Web API（`fetch`、`URL`、`AbortController`）；新布局只写 TS 和 CSS。M0 实测见 05 路线图 |
| 不用 Node | 页面里没有 Node 的需求；网络和计算交给后端进程 |
| 后端独立进程 | 语言无关；崩溃不拖垮壳；空闲整个回收；页面进程不能起子进程，所以统一由宿主代理 |
| stdio 而不是 socket | 每种语言都直接读写，没有路径长度限制，也不用清理 socket 文件 |

## 3. 语言分工

| 语言 | 负责 | 什么时候用 |
|---|---|---|
| Swift（宿主） | 窗口、菜单、热键、Keychain、WKWebView 桥、后端进程 | 新增系统能力时才改 |
| TypeScript | app 的全部界面与交互 | 每个 app 的前端 |
| Rust | 后端默认语言 | 下面两行以外的后端都用 Rust |
| Python | 本地模型推理、embedding、数据处理脚本 | Rust 生态没有或代价明显更高时 |
| Go | 需要单独打包、长期常驻且占用低的独立服务 | 非必要不用；用之前先在规划里写清理由 |

规划规则：每个功能、每个任务都要标出各部分用什么语言，统一写成 `[Swift]` `[TS]` `[Rust]` `[Py]` `[Go]`。

## 4. 模块分层

宿主的 Swift 包 `host/WispLoomKit`：

```text
ShellCore（纯逻辑：状态、manifest、连接协议 AppConnection）
   ↑               ↑                 ↑
ShellUI         ShellPlatform     AppRuntime
（WKWebView 承载） （窗口/菜单/热键）  （App 会话、后端进程、Keychain）
   ↑               ↑                 ↑
   └──────────── App（唯一装配点）────┘
```

- `AppRuntime` 只 import Foundation、Security，不 import AppKit / SwiftUI / WebKit。它通过 `ShellCore.AppConnection` 协议把一个窗口的消息收发抽象成 JSON 字符串。
- 三个中间层互不依赖；只在 `ShellController` 改 `ShellState`，只在 `WindowFactory` 建窗口。
- 每个 app 的会话（后端、命令、设置）归 `AppRuntime`；页面状态归页面自己。`ShellState` 只记录哪些 app 在运行、开了哪些窗口。

## 5. 依赖

| 部分 | 运行期依赖 | 构建期依赖 |
|---|---|---|
| 壳 `[Swift]` | 无，只用系统框架 | XcodeGen |
| 界面 `[TS]` | Preact（固定版本，约 4KB gzip；页面里直接渲染 DOM） | esbuild（只把 TSX 打成 JS + CSS）、TypeScript 类型检查 |
| 后端 `[Rust]` | 白名单：`serde`、`serde_json`、`ureq`（同步 HTTP，不引 tokio） | cargo |
| 后端 `[Py]` / `[Go]` | 每个 app 自带 `requirements.txt` / `go.mod`，版本写死 | — |

新增白名单外的依赖要先在文档里写理由。所有版本精确锁定（`Cargo.toml` 写 `=x.y.z`，`package.json` 不带 `^`）。

## 6. 目录

顶层目录一一对应第 2 节的四层，依赖只能向下：`apps` 依赖 `ui` 和 `backend`，`host` 谁都不依赖，不 import 任何 app。

```text
host/                     [Swift] 宿主
  App/                      唯一装配点（入口、CompositionRoot、AppRegistry、菜单协调、热重载）
  WispLoomKit/              Swift 包：ShellCore / ShellUI / ShellPlatform / AppRuntime
  project.yml               XcodeGen 配置
ui/                       [TS] @wisp/ui：设计系统组件、style.css、hooks、与宿主的桥、node 测试
backend/                  后端 SDK
  rust/                     [Rust] wisp-backend crate：stdio JSON Lines 循环、请求分发、取消、合并
  py/                       [Py] 单文件 wisp_backend.py
apps/<name>/              应用，壳只认这一层
  manifest.json
  ui/                       [TS] 入口 ui/main.tsx，只 import @wisp/ui
  backend/                  [Rust] / [Py] / [Go]，可选，只用 backend/ 下的 SDK
docs/  scripts/           文档、构建脚本
```

根目录只放跨层的工程文件：`Makefile`、`package.json`（npm workspace）、`tsconfig.json`、`Cargo.toml`（cargo workspace）。

构建：`make apps` 把每个 app 编成 `build/apps/<name>/`（`manifest.json`、`ui.js`、`ui.css`、`backend/<可执行文件>`），`make build` 再把它同步进 app bundle 的 `Resources/Apps`。Rust 后端的 cargo workspace 在仓库根，产物统一在 `build/cargo`。

加载顺序：bundle 内置 → `~/Library/Application Support/WispLoom/Apps/` → 设置里添加的目录。加载插件只改目录地址，不改源码。开发期用 `WISP_APPS=<repo>/build/apps` 覆盖（替换整个列表），配合热重载：`make run` 注入该变量，`make dev` 额外让 esbuild 监听 tsx。
