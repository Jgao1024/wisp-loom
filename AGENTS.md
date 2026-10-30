# AGENTS.md

Orbit：macOS 快捷键浮窗启动器（SwiftUI + AppKit），计划开源。功能清单见 `FEATURES.md`。

## 规范

- 精简优雅优先：重复两次就抽出来，不为以后写代码，配置同样要精简。
- 注释非必要不写，只标关键点。
- 不加第三方依赖。
- 只在 `ShellController` 里改 `ShellState`；只在 `WindowFactory` 里创建 `NSWindow` / `NSPanel`。
- 玻璃效果只走 `GlassStyles`，尺寸、间距、圆角只走设计令牌。
- 依赖只能向下：`ShellCore`（纯逻辑，不 import AppKit/SwiftUI）← `ShellUI` / `ShellPlatform`（互不依赖）← `App`（唯一装配点）。

## 提交前

`make build`、`make test`、`make lint` 全过，并且 Release 也编一次（Release 把警告当错误）。汇报写清跑了什么、结果如何，没验证的明说。

## 坑

- 受限沙箱下 `swift test` / `xcodebuild` 写不了 `~/Library` 的 SwiftPM 缓存，需要完整文件访问。
- 长的 `compactMap/sorted/map` 链会触发 “unable to type-check in reasonable time”，拆成循环。
- 浮窗是 `.nonactivatingPanel`，要 `canBecomeKey = true` 才能输入。
- 验证窗口：`CGWindowListCopyWindowInfo` 按 owner 过滤取 id 和 bounds，再 `screencapture -x -o -l <id>`；窗口出现后约 1 秒内可能读到动画中间帧。
- 浮窗失焦会自动关闭，其他 app 抢焦点时它会消失，“触发 + 读取 + 截图”放在同一条命令里。
- 全局快捷键的实际触发、玻璃观感无法自动验证，标注“需人工确认”。
