# AGENTS.md

Wisp Loom：macOS 快捷键浮窗启动器（SwiftUI + AppKit），计划开源。功能清单见 `FEATURES.md`。

下一阶段做应用插件平台和第一个应用 Agent，开工前读：

| 文档 | 内容 |
|---|---|
| `docs/01-architecture.md` | 进程模型、语言分工、分层、依赖、目录 |
| `docs/02-app-protocol.md` | manifest、界面桥、后端通道、热重载 |
| `docs/03-native-ui.md` | 两栏/三栏布局、菜单栏、设置窗口、组件清单 |
| `docs/04-agent-app.md` | Agent 应用的界面、数据、后端协议 |
| `docs/05-roadmap.md` | 分阶段任务，每项标注语言 |

规划和任务都要写明各部分用什么语言：`[Swift]` `[TS]` `[Rust]` `[Py]` `[Go]`。

## 规范

- 精简优雅优先：重复两次就抽出来，不为以后写代码，配置同样要精简。
- 注释非必要不写，只标关键点。
- 壳不加第三方依赖；插件后端只用 `docs/01-architecture.md` 第 5 节的白名单，版本锁死。
- 只在 `ShellController` 里改 `ShellState`；只在 `WindowFactory` 里创建 `NSWindow` / `NSPanel`。
- 玻璃效果只走 `GlassStyles`，宿主的尺寸、间距、圆角只走设计令牌。应用界面在 WKWebView 里用 TS 写，只能用 `ui/` 的设计系统组件，不传样式，观感照 macOS 原生应用。
- 新应用、新布局不改 Swift：界面都在 TS 里组合；只有新增系统能力（Keychain、通知等）才改宿主。
- 顶层目录就是四层：`host/`（Swift）、`ui/`（TS SDK）、`backend/`（后端 SDK）、`apps/`（应用）。应用只依赖 `ui/` 和 `backend/`，`host/` 不依赖任何应用；详见 `docs/01-architecture.md` 第 6 节。
- 依赖只能向下：`ShellCore`（纯逻辑，不 import AppKit/SwiftUI）← `ShellUI` / `ShellPlatform` / `AppRuntime`（互不依赖，`AppRuntime` 只 import Foundation 和 Security）← `host/App`（唯一装配点）。

## 提交前

`make build`、`make test`、`make lint` 全过，并且 Release 也编一次（Release 把警告当错误）。汇报写清跑了什么、结果如何，没验证的明说。

## 坑

- 受限沙箱下 `swift test` / `xcodebuild` 写不了 `~/Library` 的 SwiftPM 缓存，需要完整文件访问。
- 长的 `compactMap/sorted/map` 链会触发 “unable to type-check in reasonable time”，拆成循环。
- 浮窗是 `.nonactivatingPanel`，要 `canBecomeKey = true` 才能输入。
- 验证窗口：`CGWindowListCopyWindowInfo` 按 owner 过滤取 id 和 bounds，再 `screencapture -x -o -l <id>`；窗口出现后约 1 秒内可能读到动画中间帧。
- 浮窗失焦会自动关闭，其他 app 抢焦点时它会消失，“触发 + 读取 + 截图”放在同一条命令里。
- 全局快捷键的实际触发、玻璃观感无法自动验证，标注“需人工确认”。
