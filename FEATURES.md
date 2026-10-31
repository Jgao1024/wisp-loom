# Features

Wisp Loom 是 macOS 上的快捷键浮窗启动器。没有自己的桌面、Dock 或主界面，只有一个浮窗和按需打开的原生 app 窗口。

## 浮窗

- [x] 启动时自动弹出
- [x] 组合键呼出/收起（默认 ⌥Space），可在设置里改
- [ ] 长按某个修饰键呼出（`CGEventTap` + 输入监控权限引导）
- [x] 在鼠标所在屏幕居中；失焦或 Esc 关闭
- [x] 展示样式可切换，初版是 macOS 应用样式（搜索、分类标签、图标网格）。新增样式 = 一个 `LauncherStyle` 值 + 一个视图
- [ ] 浮窗主题切换

## 菜单栏与设置

- [x] 菜单栏图标：左键切换浮窗，右键菜单（设置、退出）
- [x] 设置窗口：快捷键、语言、浮窗样式
- [x] 多语言：默认中文，可切英文；新增语言 = 一个 `xx.lproj/Localizable.strings` + `Language` 加一个 case

## 应用插件（设计见 `docs/`）

- [x] 加载插件只需改目录地址，不改源码
- [x] TS + Preact 写界面（WKWebView 渲染），Rust 写后端，Python 只用于模型等生态，Go 非必要不用
- [x] 界面只能用设计系统组件（系统字体与颜色令牌），插件不能写样式
- [x] 页面桥：WKWebView message handler；后端通道：stdio JSON Lines
- [x] 开发期热重载：`make dev`（改 tsx 窗口内容替换，改后端自动重启）
- [x] 两栏 / 三栏布局、原生工具栏、app 菜单栏、toolbar 分类的设置窗口
- [x] 插件的 app 名、分类带多语言

## 应用

- [ ] Agent：模型对话，OpenAI / Anthropic 协议先行，Responses / Kiro 随后；Agent 预设、工具、skill、监控逐步补

浮窗里的 app 来自 `apps/` 下的 manifest，示例见 `apps/sample`。
