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
| 日志（实时） | ✅ 已完成，统一 WS 订阅 logs/main，snapshot + entry |
| 登录 | WKWebView + App-Bound Domains + Safari UA |
| 原生聊天（WebSocket） | ✅ 已确认收发：发送 → user_message 回声 + typing + **bot_message** 回复 |
| CI 模拟器截图 | ✅ 已验证，home / manage / chat / logs 四页正常渲染 |

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
{"op":"call","id":"c1","domain":"chat","method":"session.open","session":"<uuid>","data":{"user_name":"我"}}
{"op":"call","id":"c2","domain":"chat","method":"message.send","session":"<uuid>","data":{"content":"hi","user_name":"我"}}
{"op":"ping"}
```

**事件名已确认**（源码 `src/webui/routers/websocket/unified.py` + `chat/service.py` + `chat/message_receive/uni_message_sender.py`，
并用真实 WS 端到端复现过）。`domain:"chat"` 下按 `data.type` 区分：

| event/type | 含义 | 处理 |
| --- | --- | --- |
| `session_info` | 会话元信息 | 忽略 |
| `history` | `data.messages`：`[{type:"bot"|"user", content, segments?}]` | 打开会话时回填 |
| `system` | `data.content` 欢迎语/提示 | 居中提示气泡 |
| `user_message` | 用户消息；自己的会回声，`data.origin` 以 `:<clientSessionId>` 结尾 | 自己的回声跳过，别人发的显示 |
| `typing` | `data.is_typing` | 控制「正在输入」 |
| **`bot_message`** | **机器人回复**；`data.content`，富文本另有 `data.segments` | 追加机器人气泡 |
| `error` | `data.content` | 错误提示 |

要点：**只有 `bot_message` 才是机器人回复**（别再对「任何带 content 的 event」追加，否则自己的
`user_message` 回声会被当成机器人消息重复显示）。

## 5.1 日志 WebSocket（真实日志页）

浏览器日志页**不是**用独立的 `/ws/logs`，而是在同一条 `/api/webui/ws` 上订阅：

```jsonc
{"op":"subscribe","id":"l1","domain":"logs","topic":"main","data":{"replay":200}}
// -> {"op":"response","ok":true,"data":{"domain":"logs","topic":"main"}}
// -> {"op":"event","domain":"logs","event":"snapshot","data":{"entries":[{id,timestamp,level,module,message,...}]}}
// -> {"op":"event","domain":"logs","event":"entry","data":{"entry":{...}}}   // 之后每条实时日志
```

`LogsClient` 就是这么实现的（同一套 cookie 握手），`LogsView` 展示并按 ERROR/WARNING 过滤。
（`/ws/logs` 存在但只回放历史、不接实时广播，前端未使用，iOS 也不应使用。）

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
1. `deploymentTarget` = iOS 26.0，只能 iOS 26+。
2. 未签名 IPA，需自签（Sideloadly / AltStore）。

红线：
- 不要动 `/opt/dsh-auth/data/session.key`（一改全部会话失效）。
- 改网关后必须 `systemctl restart dsh-auth` 并 `curl /healthz` 验证。
- 面板数据文件勿用 sudo 写（会变 root 属主，网关读不到）。
- Turnstile `enabled:true`，这是登录必须走 WebView 的原因，别在原生剔除。

## 8. 代码结构

```
MaiBot/
├── MaiBotApp.swift / Info.plist / MaiBot.entitlements
├── Core/  Theme, Models, APIClient, AuthStore, ChatClient, LogsClient, TestSupport
└── Features/  RootView(含原生聊天), LoginView, DashboardView, BotsView,
              ActivityView, ModelListView, SettingsView, LogsView
```

## 9. 给新会话的第一句话（直接粘贴）

> 接手 MaiBot iOS（https://github.com/Lbcheng1145/maibot-ios），先读仓库根目录 HANDOVER.md。
> 当前进度：首页/机器人/活动流/模型/设置已完成并在 CI 模拟器截图验证；原生聊天已确认收发
> （机器人回复事件名 = bot_message）；真实日志页已用统一 WS 订阅 logs/main 实现。
> 下一步：跑一次 Actions，下载 app-screenshots artifact 看 home/manage/chat/logs 四页，
> chat 页应能看到机器人回复气泡。接口与协议见 HANDOVER §5/§5.1，不要改 SSO 网关。