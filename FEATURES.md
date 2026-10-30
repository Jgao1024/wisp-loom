# Features

Orbit 是 macOS 上的快捷键浮窗启动器。没有自己的桌面、Dock 或主界面，只有一个浮窗和按需打开的原生 app 窗口。

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

## 插件

- [ ] 加载插件只需改包地址，不改源码
- [ ] Rust 写后端能力，TypeScript 写界面
- [ ] 界面（按钮、窗口、布局、样式）全部映射到原生组件，不用 WebView
- [ ] 壳与插件的协议（Unix socket + JSON：界面树 patch 和事件）
- [ ] 插件的 app 名、分类带多语言

目前浮窗里的 app 是 `AppDescriptor.samples` 占位数据。
