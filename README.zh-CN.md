# EdgeShelf

[English](README.md) | **中文**

[![Build](https://github.com/tianyk/EdgeShelf/actions/workflows/build.yml/badge.svg)](https://github.com/tianyk/EdgeShelf/actions/workflows/build.yml)

![EdgeShelf](docs/screenshot-zh.png)

EdgeShelf 是一个面向 macOS 26/27 的轻量拖拽暂存搁板，也是
[Dropshelf](https://pilotmoon.com/dropshelf/) 的干净重实现。

把文件、文件夹、图片、链接或文本拖到屏幕左/右边缘，搁板会出现并保留这些内容，直到你把它们拖到别处。

原版 Dropshelf（Build 1729，2021 年）在 macOS 26 上可能因为 Core Drag 重入而卡死；诊断记录见
[DROPSHELF-NOTES.md](DROPSHELF-NOTES.md)（英文）。

## 功能

- 把文件、文件夹、文本、图片、链接拖到左/右屏幕边缘。
- 搁板直接引用原始文件或文件夹，不复制内容，所以超大文件也能瞬间放入，且不占额外空间。
- 每个文件项目都用 kqueue vnode watcher 监听：原文件被删除（包括移到废纸篓）时卡片立即消失；在同一卷内重命名或移动时，卡片的路径和名称会自动更新。
- 同一次拖入的多个文件默认合并成一张组卡片。点击展开成员，直接拖动组卡片即可一次移出全部文件。右键菜单提供全部打开、在访达中显示全部、拷贝全部、拆分为单独项目和移除这一组；也可以在偏好设置里关闭合并。
- 粘贴的图片和通过文件承诺（file promise）接收的文件保存在 `~/Library/Application Support/EdgeShelf/Items`，其余内容都留在原处。
- 搁板高度随内容在 220–560pt 之间变化；拖拽过程中冻结高度，避免 macOS 26 的拖拽重入问题。
- 暖纸色浅色主题 / graphite 深色主题，陶土色强调色、克制的斜纹和柔和阴影。
- 64pt 卡片：按类型着色的缩略图、真实图片预览、文件名、类型和大小；悬停显示移除按钮。
- 鼠标离开后立即收成边缘 8×96pt 渐变胶囊；鼠标移到边缘再展开。
- 在 macOS「显示桌面」状态下仍然可用：边缘窗口会重建，因此仍可把文件拖到搁板上。
- 右键菜单：打开、在访达中显示、拷贝、从搁板移除，带快捷键；
  另有“清空搁板”，作用于整个搁板。
- 六种联合国官方语言 +“跟随系统”。
- 不需要辅助功能、输入监控或屏幕录制权限。
- 不使用 `CGWindowListCreate`，主线程不做同步 XPC / `NSTask`。
- 产品名 **EdgeShelf** 始终保留英文，不翻译。

## 语言

在 **偏好设置 → 语言** 中选择：

| 语言 | 本地名称 | 布局 |
|---|---|---|
| 跟随系统 | — | 系统 |
| 英语 | English | LTR |
| 中文 | 中文 | LTR |
| 法语 | Français | LTR |
| 西班牙语 | Español | LTR |
| 俄语 | Русский | LTR |
| 阿拉伯语 | العربية | RTL 搁板 |

默认是 **跟随系统**，会解析为上面六种语言之一（无法识别时回退到英语）。
阿拉伯语会把搁板的头部和卡片镜像为 RTL；偏好设置窗口和系统菜单仍跟随系统布局方向。

阿拉伯语预览：[`docs/screenshot-ar.png`](docs/screenshot-ar.png)。

## 界面

- 300pt 面板；高度随项目数量在 220–560pt 之间变化，拖拽中冻结。
- 暖纸色浅色主题 / graphite 深色主题，陶土色强调色、轻微斜纹和柔和外阴影。
- 64pt 卡片：类型色缩略图、文件名、类型和大小；悬停显示移除按钮。
- 收起后是边缘 8×96pt 陶土色渐变胶囊，带柔光；鼠标移到边缘展开。
  预览：[`docs/tab.png`](docs/tab.png)。
- 所有界面文案集中在 [`Sources/L10n.swift`](Sources/L10n.swift)。

## 构建

```bash
./build.sh              # 当前架构
UNIVERSAL=1 ./build.sh  # arm64 + x86_64 通用包
open build/EdgeShelf.app
```

需要 Xcode 26（或对应的命令行工具）。App 使用本地 ad-hoc 签名；换到另一台 Mac 首次打开时右键 → 打开。

## GitHub Actions

[`.github/workflows/build.yml`](.github/workflows/build.yml) 会在每次推送到 `main`、每个 Pull Request 时构建通用包，运行自测，并上传 `EdgeShelf-<sha>.zip`、`.dmg` 和 SHA-256 校验文件作为 workflow artifact。

推送 tag 会自动创建 GitHub Release，并附上同样的文件：

```bash
git tag v0.1.0
git push origin v0.1.0
```

构建使用 ad-hoc 签名，**没有公证**。如果要分发给其他 Mac，建议配置 Developer ID 证书和公证步骤（例如使用 `MACOS_CERTIFICATE`、`MACOS_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` secrets），然后在打包前对 `.app` 执行 `codesign` 和 `notarytool`。

## 使用

- 把内容拖到屏幕左/右边缘，搁板出现。
- 松手后搁板直接引用原始文件，不会额外复制。
- 鼠标移开立即收成边缘胶囊；移到胶囊附近再展开。
- 右键项目：打开 / 在访达中显示 / 拷贝 / 从搁板移除。
- 一次拖入多个文件时，它们会合并成一张组卡片。点击卡片展开成员，直接拖动卡片即可一次移出全部文件。右键组卡片可全部打开、在访达中显示全部、拷贝全部、拆分为单独项目或移除这一组；也可以在偏好设置里关闭合并。
- 把项目拖到 Finder、邮件、Slack 等。拖出的是原始文件路径，属于复制操作，
  源文件不会被移动。
- 菜单栏 → 偏好设置：边缘、行为、语言。

旧版本留下的副本会在首次启动时清理（前提是原文件还在）。如果原文件早已不存在，则保留那份副本，因为它是仅剩的内容。

## 测试

```bash
# 数据模型 + 剪贴板 + 存储内容 + 文件监听往返
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --self-test

# 添加演示项目并显示左搁板
open build/EdgeShelf.app --args --demo

# 不截屏，直接把搁板渲染到 /tmp/edgeshelf-snapshot.png
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --snapshot

# 渲染收起和展开的组卡片
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --snapshot-groups
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --snapshot-groups --expand-groups

# 强制语言做截图或手动检查
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --lang zh --snapshot --snapshot-many
```

`--demo`、`--snapshot*`、`--self-test` 和 `--debug-*` 都跑在
`$TMPDIR/EdgeShelf-Debug` 下一个一次性数据目录里，不会碰你实际使用的搁板。

## 手动测试清单

1. 从 Finder 拖一个文件到左边缘，搁板出现，松手放入。
2. 鼠标移开，立即收成边缘胶囊。
3. 移到边缘胶囊，搁板展开。
4. 把文件从搁板拖回原文件夹，不应出现“是否替换”。
5. 在 Finder 里重命名文件，卡片名称和路径自动更新。
6. 在 Finder 里删除原文件，搁板上的卡片随即消失。
7. 从浏览器/编辑器拖一段文本到右边缘。
8. 右键项目，试打开、在访达中显示、拷贝。
9. 在偏好设置里切换语言，搁板和偏好设置立即更新。
10. 退出再启动，搁板、项目和语言选择都恢复。
11. 一次拖入多个文件；出现一张组卡片。拖动组卡片，所有文件一起到达。点击展开后，可以单独拖出其中一个成员；右键组卡片可执行整组操作。

## 已知限制

- 每条边每个显示器只有一个搁板；Dropshelf 支持同一条边多个搁板。
- 上下边缘还没实现。
- 还没有 Quick Look、打开方式子菜单；跨组多选尚未实现，但组内的多个文件可以一次拖出。
- 运行中且文件仍在同一卷内时，重命名/移动会被跟随。App 未运行时发生的移动，或跨卷移动，会按删除处理。外接磁盘未挂载时项目会保留，重新挂载后恢复。
- 重命名项目所在的父文件夹，会在下次启动、唤醒或挂载时更新；文件自身的 vnode 收不到祖先目录变化。
- 某些网络卷不提供 kqueue 事件。这类卷上的变化只在启动、唤醒或挂载/卸载时检查，不是即时的。
- 搁板状态按显示器 ID 保存；显示器重连后 ID 变化时，原搁板项目不会显示在新显示器上。
- 阿拉伯语会镜像搁板头部和卡片；偏好设置窗口和状态菜单仍跟随系统布局方向。
- App 没有公证，只在本地构建和签名。

## 项目结构

```
Sources/
  main.swift                      入口、自测
  AppDelegate.swift               菜单栏和 App 生命周期
  DragMonitor.swift               全局鼠标拖拽检测 + 边缘轮询
  ShelfManager.swift              状态、持久化、边缘窗口、接收项目
  ShelfWindow.swift               固定 frame 的边缘窗口、显示状态
  ShelfView.swift                 搁板面板和项目卡片
  Theme.swift                     尺寸、配色、背景、胶囊、空状态
  L10n.swift                      所有界面文案和六种语言表
  FileWatcher.swift               kqueue 文件删除/重命名/移动监听
  Store.swift                     JSON 状态 + 粘贴图片/文件承诺的存储
  Models.swift                    ShelfItem/ShelfState/ShelfEdge
  Preferences.swift               UserDefaults
  PreferencesWindowController.swift
```

使用 AppKit 构建，无第三方依赖。
