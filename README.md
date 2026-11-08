# MaiBot iOS

[![Build](https://github.com/Lbcheng1145/maibot-ios/actions/workflows/build.yml/badge.svg)](https://github.com/Lbcheng1145/maibot-ios/actions/workflows/build.yml)

一个 MaiBot 面板的原生 iOS 客户端，用 SwiftUI + Liquid Glass 重写网页版的交互，
直接对接现有的 host API。

> 非官方客户端。网页版仍是功能全集，这里覆盖高频操作。

## 界面

| 标签 | 内容 |
| --- | --- |
| **概览** | 宿主状态、机器人数量、选中实例详情、启动/重启/停止 |
| **机器人** | 列表、状态、逐项控制、切换当前实例 |
| **日志** | 实时跟随、自动刷新、等宽字体 |
| **配置** | WebUI 设置只读概览（改配置请回网页版） |
| **设置** | 主题、服务器地址、退出登录 |

配色直接取自网页版的 CSS 变量：深色主题 `#0B1013` 底 + 薄荷绿 `#00BB7F`
强调，另有一套「复古纸张」米色主题。

## 技术选型

| 项 | 选择 |
| --- | --- |
| 最低版本 | iOS 26.0 |
| 构建验证 | GitHub Actions，Xcode 26.3 / iOS 26 SDK，0 error |
| UI | SwiftUI、`@Observable`、`NavigationStack`、iOS 26 浮动标签栏 |
| 玻璃质感 | `.glassEffect()`、`GlassEffectContainer`、`.buttonStyle(.glass)` |
| 登录 | 原生 SwiftUI `WebView` + `WebPage` 跑完整 SSO 流程 |
| 会话 | Cookie 存 Keychain（`kSecAttrAccessibleAfterFirstUnlock`） |
| 网络 | `URLSession` + `async/await`，无第三方依赖 |

> **关于 iOS 27**：代码已用尽 iOS 26 引入的全部新 UI API（Liquid Glass、
> 原生 `WebView`、`Tab`、`scrollEdgeEffectStyle`、`MeshGradient`）。
> 当前 CI 镜像最高提供 Xcode 26.3 / iOS 26 SDK，因此 deployment target
> 设为 26.0；Xcode 27 发布后把 `project.yml` 里的 `deploymentTarget`
> 改成 `"27.0"` 即可，源码无需改动。

## 为什么登录要走 WebView

面板只发 HttpOnly cookie，原生代码拿不到密码换 cookie。所以在系统网页视图里
完成 SSO（Cloudflare Access / GitHub / 硬件密钥都在这里正常工作），再从共享
cookie store 里取出 `maibot_host_session_*`。

## 两个必须知道的服务端约定

1. 写 `/api/host/*` 必须带 `X-MaiBot-Host: 1`，否则 403「缺少管理请求标识」
2. 服务端的 CSRF 检查在 **Origin 头缺失时直接放行**。`URLSession` 默认不设
   Origin，所以**不要**手动加，加了反而进入 Host 比对逻辑

## 构建

### 本地（Xcode 26+）

```bash
brew install xcodegen
xcodegen generate
open MaiBot.xcodeproj
```

或者把 `MaiBot/` 目录直接拖进一个新的 iOS App 工程。

### CI

推送 `main` 会在 macOS runner 上编译模拟器版本（无签名），日志作为 artifact 保存：

```
.github/workflows/build.yml
```

首次运行 `-` 若报 `xcodegen` 未找到，CI 会自动 `brew install`。

## 结构

```
MaiBot/
├── MaiBotApp.swift          入口 + 主题注入
├── Info.plist
├── Assets.xcassets
├── Core/
│   ├── Theme.swift          配色、玻璃卡片、状态胶囊
│   ├── Models.swift         Bot / HostMode / Settings 等 Codable
│   ├── APIClient.swift      URLSession 封装
│   └── AuthStore.swift      Keychain 会话 + cookie 抓取
└── Features/
    ├── RootView.swift       登录态路由 + 标签栏
    ├── LoginView.swift      原生 WebView 登录
    ├── DashboardView.swift
    ├── BotsView.swift
    ├── LogsView.swift
    ├── ConfigView.swift
    └── SettingsView.swift
```

## 许可

MIT