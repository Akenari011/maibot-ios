# MaiBot iOS

[![Build](https://github.com/Lbcheng1145/maibot-ios/actions/workflows/build.yml/badge.svg)](https://github.com/Lbcheng1145/maibot-ios/actions/workflows/build.yml)

一个 MaiBot 面板的原生 iOS 客户端，SwiftUI + Liquid Glass，直接对接现有 host API。

> 非官方客户端。网页版仍是功能全集，这里覆盖高频操作。

## 界面

| 标签 | 内容 |
| --- | --- |
| **概览** | 宿主状态、机器人数量、选中实例详情、启动/重启/停止 |
| **机器人** | 列表、状态、逐项控制、切换当前实例 |
| **日志** | 实时跟随、自动刷新、等宽字体 |
| **配置** | WebUI 设置只读概览 |
| **设置** | 主题、服务器地址、退出登录 |

配色取自网页版 CSS 变量：深色 `#0B1013` + 薄荷绿 `#00BB7F`，另有「复古纸张」主题。

## 登录方式兼容性（重要）

登录页在 WKWebView 里跑。WKWebView 不是完整的浏览器，不同登录方式可用性不同：

| 方式 | 状态 | 说明 |
| --- | --- | --- |
| 动态验证码 TOTP | ✅ 可用 | 纯表单，无依赖 |
| 邮箱验证码 | ✅ 可用 | 纯表单，无依赖 |
| 硬件密钥 FIDO2（USB / NFC） | ⚠️ 需要配置 | 依赖 App-Bound Domains，已配置；需签名后生效 |
| Passkey / iCloud 钥匙串 / Windows Hello | ⚠️ 受限 | 需要 Associated Domains，**免费 Apple ID 不支持该能力**，需付费开发者账号 |
| GitHub 登录 | ❌ 不可靠 | GitHub 拒绝内嵌 webview 的 OAuth。已用 Safari UA 伪装尝试，但不保证通过 |

### 为什么不改服务端就只能做到这个程度

硬件密钥的问题在 app 侧能解：`WKWebViewConfiguration.limitsNavigationsToAppBoundDomains = true`
+ Info.plist 的 `WKAppBoundDomains`，WebAuthn 才有机会弹出系统验证界面。已全部配置。

GitHub 的问题在 app 侧解不了：GitHub 会检测 UA 拒绝内嵌浏览器，而唯一被 GitHub 接受的
系统浏览器（`ASWebAuthenticationSession`）登录后，cookie 属于 Safari，原生 app 拿不到。
要打通只有一条路——服务端在登录完成时 302 到 `maibot://auth?t=<ticket>`，app 用票换 cookie。
那需要改网关，本版本没做。

## 技术选型

| 项 | 选择 |
| --- | --- |
| 最低版本 | iOS 26.0 |
| 构建验证 | GitHub Actions，Xcode 26.3 / iOS 26 SDK，0 error |
| UI | SwiftUI、`@Observable`、`NavigationStack`、iOS 26 浮动标签栏 |
| 玻璃质感 | `.glassEffect()`、`GlassEffectContainer`、`.buttonStyle(.glass)` |
| 登录 | `WKWebView` + App-Bound Domains（WebAuthn 必需） |
| 会话 | Cookie 存 Keychain（`kSecAttrAccessibleAfterFirstUnlock`） |
| 网络 | `URLSession` + `async/await`，无第三方依赖 |

> iOS 27：CI 镜像最高 Xcode 26.3 / iOS 26 SDK。Xcode 27 发布后把 `project.yml`
> 的 `deploymentTarget` 改成 `"27.0"` 即可，源码无需改动。

## 两个必须知道的服务端约定

1. 写 `/api/host/*` 必须带 `X-MaiBot-Host: 1`，否则 403「缺少管理请求标识」
2. CSRF 检查在 **Origin 头缺失时直接放行**；`URLSession` 默认不设 Origin，别手动加

## 构建

```bash
brew install xcodegen
xcodegen generate
open MaiBot.xcodeproj
```

签名时确认 target 的 Signing & Capabilities 里 Associated Domains 已开启
（entitlements 已写在 `MaiBot/MaiBot.entitlements`）。

## 结构

```
MaiBot/
├── MaiBotApp.swift          入口 + 主题注入
├── Info.plist               WKAppBoundDomains
├── MaiBot.entitlements      associated-domains (webcredentials)
├── Assets.xcassets
├── Core/
│   ├── Theme.swift          配色、玻璃卡片、状态胶囊
│   ├── Models.swift         Bot / HostMode / Settings
│   ├── APIClient.swift      URLSession 封装
│   └── AuthStore.swift      Keychain 会话 + cookie 抓取
└── Features/
    ├── RootView.swift       登录态路由 + 标签栏
    ├── LoginView.swift      WKWebView + App-Bound Domains
    ├── DashboardView.swift
    ├── BotsView.swift
    ├── LogsView.swift
    ├── ConfigView.swift
    └── SettingsView.swift
```

## 许可

MIT