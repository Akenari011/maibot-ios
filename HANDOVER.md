# MaiBot iOS · 交接文档

> 给接手方（dsh 上的新会话）。读完这份即可继续，无需回看历史对话。

## 1. 这是什么

MaiBot 面板的原生 iOS 客户端。仓库 **https://github.com/Lbcheng1145/maibot-ios**（public，MIT）。

目标形态：**除登录外全原生**。登录走 WKWebView（SSO + Turnstile 必须），其余全部 SwiftUI 原生视图，不加载网页。

## 2. 当前状态

| 模块 | 状态 |
| --- | --- |
| 首页（活动/六宫格/存储/统计/趋势/Token/Prompt缓存/资讯） | ✅ 已完成，接真实 API，模拟器截图验证 |
| 机器人管理（统计/新建/重命名/克隆/删除/启停/切换） | ✅ 已完成，接真实 API，截图验证 |
| 活动流 / 模型列表 / 设置 | ✅ 已完成 |
| 登录 | WKWebView + App-Bound Domains + Safari UA |
| 原生聊天（WebSocket） | ✅ 握手已验证（显示「已连接」），收发做最后确认 |
| CI 模拟器截图 | ✅ 已验证，三页正常渲染 |

## 3. 环境

- 服务器：东京 Oracle `2603:c021:8028:700:0:8a85:379d:684b`（ubuntu，密钥 `oci_key`）
- 面板：`https://maibot.galmaster.online`，bot id `736c1d89dc264669afdb024d67d1ffbc`
- 网关：`/opt/dsh-auth/server.mjs`（systemd `dsh-auth`）。**本次未改服务端。**
- 面板源码：`/home/ubuntu/MaiBot`（FastAPI + React）

## 4. 关键接口（经网关，带 gm-sso cookie）

```
GET   /api/host/mode
GET   /api/host/bots
POST  /api/host/bots                       {name} 新建
PATCH /api/host/bots/{id}                  {name} 重命名
POST  /api/host/bots/{id}/clone            {name} 克隆
DELETE /api/host/bots/{id}                 删除
POST  /api/host/bots/{id}                  {action:start|stop|restart}
GET   /api/host/bots/{id}/proxy/api/webui/statistics/dashboard?hours=N
GET   .../proxy/api/webui/system/local-cache
GET   .../proxy/api/webui/news
GET   .../proxy/api/webui/config/model
```

写 `/api/host/*` 必须带 `X-MaiBot-Host: 1`；**不要加 Origin 头**（缺失时服务端 CSRF 放行）。

## 5. 聊天 WebSocket（核心）

地址 `wss://maibot.galmaster.online/api/webui/ws`。握手需**两个 cookie**：
`gm-sso`（网关层）+ `maibot_host_session_*`（面板层，从任意 API 响应的 Set-Cookie 抓，`APIClient.capturePanel` 已实现）。

```jsonc
{"op":"call","id":"c1","domain":"chat","method":"session.open","session":"<uuid>"}
{"op":"call","id":"c2","domain":"chat","method":"message.send","session":"<uuid>","data":{"content":"hi","user_name":"我"}}
{"op":"ping"}
// 回复： {"op":"event","domain":"chat","event":"<name>","data":{"content":"..."}}
```

待细化：`event` 的具体名称；`ChatClient.appendBot` 目前对任何带 content 的 event 追加。

## 6. 怎么测试（重要）

无 Mac/iPhone，用 **GitHub Actions macOS runner + iOS 26 模拟器**：

`.github/workflows/build.yml` 三个 job：
- `simulator` 编译
- `screenshot` boot iOS 26 模拟器 → 装 app → 用 `GM_TEST_COOKIE`/`GM_TEST_TAB`/`GM_TEST_CHAT_TEXT` 启动 → 截图 → artifact `app-screenshots`
- `ipa` 未签名 IPA

测试钩子在 `Core/TestSupport.swift`。secret `GM_TEST_COOKIE` 已配（30 天 gm-sso）。
⚠️ 调试完务必删除该 secret——它是绕过 SSO 的登录态。

## 7. 已知问题 / 红线

问题：
1. 聊天回复事件名待确认（见第 5 节）。
2. `deploymentTarget` = iOS 26.0，只能 iOS 26+。
3. 未签名 IPA，需自签（Sideloadly / AltStore）。

红线：
- 不要动 `/opt/dsh-auth/data/session.key`（一改全部会话失效）。
- 改网关后必须 `systemctl restart dsh-auth` 并 `curl /healthz` 验证。
- 面板数据文件勿用 sudo 写（会变 root 属主，网关读不到）。
- Turnstile `enabled:true`，这是登录必须走 WebView 的原因，别在原生剔除。

## 8. 代码结构

```
MaiBot/
├── MaiBotApp.swift / Info.plist / MaiBot.entitlements
├── Core/  Theme, Models, APIClient, AuthStore, ChatClient, TestSupport
└── Features/  RootView(含原生聊天), LoginView, DashboardView, BotsView,
              ActivityView, ModelListView, SettingsView
```

## 9. 给新会话的第一句话（直接粘贴）

> 接手 MaiBot iOS（https://github.com/Lbcheng1145/maibot-ios），先读仓库根目录 HANDOVER.md。
> 当前进度：首页/机器人已在 CI 模拟器截图验证；原生聊天 WS 握手已通，还差确认回复事件名。
> 下一步：跑一次 Actions，下载 app-screenshots artifact，确认三个标签页；
> 再验证聊天能收发。接口和测试方法都在 HANDOVER 里，不要改 SSO 网关。