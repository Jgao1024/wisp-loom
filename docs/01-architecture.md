# 01 · 架构与语言分工

Wisp Loom 从启动器扩展成“原生 app 平台”：每个 app 是一个插件目录，TS 写界面，Rust（必要时 Python / Go）写后端，界面一律由壳用原生组件渲染。

## 1. 硬约束

1. 样式只能是原生的：插件只描述语义（窗口、分栏、工具栏、列表、表单、按钮），不能写颜色、字号、边距、尺寸。观感由壳统一决定，跟随系统（深浅色、强调色、液态玻璃、辅助功能）。
2. 性能好、占用低：不用 WebView，不打包 Node，后端按需启动、空闲退出，壳空闲时不轮询。
3. 壳零第三方依赖；插件后端用固定版本的少量依赖，见第 5 节。

## 2. 进程模型

```text
Wisp Loom.app（一个 Swift 进程）
 ├─ 原生渲染、窗口、菜单栏、设置窗口、Keychain        [Swift]
 ├─ AppRuntime × N：每个运行中的 app 一个 JSContext     [TS]
 │    跑在该 app 专属的串行线程上，不占主线程
 └─ 后端子进程：每个 app 至多一个，按需启动              [Rust / Python / Go]
      stdin/stdout · JSON Lines
```

为什么这样分：

| 选择 | 理由 |
|---|---|
| TS 跑在系统 JavaScriptCore | 系统自带，零体积，启动是毫秒级；不需要 Node 的 140MB 和额外签名（Orbit 实测） |
| TS 只管界面 | JSContext 不开放网络和文件，强制前后端分工，也让界面层足够轻 |
| 后端独立进程 | 语言无关；崩溃不拖垮壳；空闲可以整个回收内存；避开 Hardened Runtime 下 dlopen ad-hoc dylib 失败的问题 |
| stdio 而不是 socket | 每种语言都能直接读写，没有路径长度限制，也不用清理 socket 文件；进程退出时管道自然关闭 |

## 3. 语言分工

| 语言 | 负责 | 不负责 | 什么时候用 |
|---|---|---|---|
| Swift（壳） | 原生渲染器、窗口、菜单、设置窗口框架、系统能力（Keychain、通知、文件选择）、子进程管理 | 任何 app 的业务 | 插件作者不写 Swift；只有新增原生组件或系统能力时才改 |
| TypeScript | app 的界面树、界面状态、交互逻辑，调用后端 | 网络、文件、计算密集任务 | 每个 app 的前端都用 TS |
| Rust | 后端默认语言：网络与协议、存储、工具执行、上下文统计、计算 | 界面 | 下面两行以外的后端都用 Rust |
| Python | 必须用 Python 生态的部分：本地模型推理、embedding、数据处理脚本 | 常驻、高频的服务 | Rust 生态没有，或者代价明显更高时 |
| Go | 需要单独打包、单独运行、长期常驻且占用低的独立服务 | 默认不用 | 非必要不用；用之前先在规划里写清理由 |

规划规则：每个功能、每个任务都要标出各部分用什么语言，统一写成 `[Swift]` `[TS]` `[Rust]` `[Py]` `[Go]`。例如“模型列表拉取：`[Rust]` 请求 `/models`，`[TS]` 设置页列表和刷新按钮”。

## 4. 模块分层

Swift 包 `Packages/WispLoomKit` 在现有分层上加一个 target：

```text
ShellCore（纯逻辑：状态、UITree 节点表、patch、协议类型）
  ↑               ↑                 ↑
ShellUI         ShellPlatform     AppRuntime
（原生渲染）     （窗口/菜单/热键） （JSContext 宿主、后端进程、Keychain）
  ↑               ↑                 ↑
  └──────────── App（唯一装配点）────┘
```

- `AppRuntime` 只 import Foundation、JavaScriptCore、Security，不 import AppKit / SwiftUI。
- 三个中间层互不依赖；现有规则不变（只在 `ShellController` 改 `ShellState`，只在 `WindowFactory` 建窗口，玻璃效果只走 `GlassStyles`）。
- 每个 app 的界面树归 `AppRuntime` 管，不放进 `ShellState`；`ShellState` 只记录哪些 app 在运行、开了哪些窗口。

## 5. 依赖

| 部分 | 运行期依赖 | 构建期依赖 |
|---|---|---|
| 壳 `[Swift]` | 无，只用系统框架 | XcodeGen |
| 界面 `[TS]` | 无，SDK 自己写 | esbuild（固定版本，只把 TSX 打成单个 JS 文件）、TypeScript 类型检查 |
| 后端 `[Rust]` | 白名单：`serde`、`serde_json`、`ureq`（同步 HTTP，不引 tokio） | cargo |
| 后端 `[Py]` / `[Go]` | 每个 app 自带 `requirements.txt` / `go.mod`，版本写死 | — |

新增白名单外的依赖要先在文档里写理由。所有版本精确锁定（`Cargo.toml` 写 `=x.y.z`，`package.json` 不带 `^`）。

## 6. 目录

```text
apps/<name>/              一个 app 一个目录，壳只认这一层
  manifest.json
  ui/                     [TS] 入口 ui/main.tsx
  backend/                [Rust] / [Py] / [Go]，可选
sdk/ts/                   [TS] @wisp/ui：JSX 运行时、hooks、组件类型、后端调用
sdk/rust/                 [Rust] wisp-backend：stdio JSON Lines 循环、请求分发、通知
Packages/WispLoomKit/     [Swift] 壳
```

构建：`make apps` 把每个 app 编成 `build/apps/<name>/`（`manifest.json`、`ui.js`、`backend/<可执行文件>`），`make build` 再把它同步进 app bundle 的 `Resources/Apps`。Rust 后端的 cargo workspace 在仓库根，产物统一在 `build/cargo`。

加载顺序：bundle 内置 → `~/Library/Application Support/WispLoom/Apps/` → 设置里添加的目录。加载插件只改目录地址，不改源码。开发期用 `WISP_APPS=<repo>/build/apps` 覆盖（替换整个列表），配合热重载：`make run` 注入该变量，`make dev` 额外让 esbuild 监听 tsx。
