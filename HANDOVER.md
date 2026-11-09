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
| 管理页（设置索引） | ✅ 已完成（配置/资源/扩展/高级工具/运行日志/系统）|
| 设置页 | ✅ 6 Tab（通用/机器人/外观/安全/其他/关于）；安全页接 auth/update、auth/regenerate |
| 机器人管理 | ✅ PageFrame(圆角8/2px)+DataPanel、3 秒轮询、详情折叠 |
| 日志（实时） | ✅ 棕色终端 + 工具栏（搜索/来源/筛选/跟随/导出/清空/字号行距）；自适应 ws |
| 子页面 | ✅ 模型列表/统计/麦麦设置(只读JSON)/插件(installed)/长期记忆(sources)/提示词(prompts)/文件(files)/资讯(news)/适配器(adapter-config)/推理(reasoning)/市场(market)/学习(learning)；插件市场·推理过程·适配器·学习受接口鉴权/参数限制暂占位（提供"在网页版打开"深链） |
| 登录 | WKWebView + App-Bound Domains + Safari UA |
| 原生聊天 | ✅ 会话列表(真实 /api/chat/sessions) + 对话页(自适应 ws、头像/玻璃状态头/消息「名称·时间」分组) |
| CI 模拟器截图 | ✅ 七页 home/manage/chat/logs/settings/bots/room；模拟器冷启动约 5-7 分钟 |

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
  - `GM_TEST_TAB` 可选：home / manage / chat / logs / settings / bots / room / dark / stats / config / plugins / memory / prompts / files
  - 截图与 IPA **仅在工作流手动触发(workflow_dispatch)或 commit 含 `[shot]` 时运行**；普通 push 只做编译（约 3 分钟，适合快速迭代）
  - ⚠️ CI 的 `GM_TEST_COOKIE` 只含 `gm-sso`、无面板会话 `maibot_host_session`，因此**需要面板会话的动态页（日志、聊天室）在 CI 截图里连不上**；真机 WebView 登录会同时拿到两个 cookie，功能正常。
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
├── Core/  Theme, Motion, DesignTokens, Models, APIClient, AuthStore,
│         ChatClient, LogsClient, TestSupport
└── Features/  RootView(含 Tab 栏/聊天室), LoginView, DashboardView, BotsView,
              ChatListView, ManagementIndexView, ActivityView, ModelListView,
              SettingsView, LogsView, StatisticsView, ConfigBrowserView,
              PluginsView, MemorySourcesView, PromptsView, FilesView, NewsListView
```

## 9. 给新会话的第一句话（直接粘贴）

> 接手 MaiBot iOS（https://github.com/Lbcheng1145/maibot-ios），先读仓库根目录 HANDOVER.md。
> 当前进度：首页/聊天(列表+对话)/管理/设置(6Tab·浅深主题·强调色)/机器人/日志(棕终端·来源多选·日期筛选)/
> 模型/统计/麦麦设置(只读)/插件/长期记忆/提示词/文件/资讯 共 18 个真实页面已完成；受限 3 页(插件市场/推理过程/
> 适配器/学习)保留占位并提供"在网页版打开"深链。机器人代理 401 不再触发登出；WS 后台自动断开。
> 下一步：按需手动触发 Actions 下载 app-screenshots（15 个 tab）核验；接口与协议见 HANDOVER §5/§5.1，不要改 SSO 网关。
## 10. 近期变更（iOS 端）

- **主题**：浅色 / 深色 / 跟随系统 + 自定义强调色（强调色驱动全局调色板）。
- **新增真实页面**：统计、麦麦设置（只读 JSON 树）、插件、长期记忆、提示词、文件、资讯。
- **日志**：来源多选（持久化）、级别与日期筛选、暂停跟随并显示 +N 新增、清空二次确认、后台断开 WS、失败可重连。
- **聊天**：对端名称（session_info）、自己消息 sender/time、回车发送、未连接/空输入禁用发送、后台断开 WS、自动滚底尊重 reduce-motion。
- **健壮性**：机器人代理 401 不再触发登出（提示“机器人会话未就绪”）；连接 12s 看门狗；子页错误统一可重试。
- **CI**：普通 push 只编译（约 3 分钟）；手动触发或 commit 含 [shot] 才截图（15 个 tab）。

## 11. 核验记录（最近一次全量截图）

- 触发：手动 workflow_dispatch；产物 artifact id 13642501070（app-screenshots）。
- 覆盖 19 个 tab：home / manage / chat / room / logs / settings / bots / dark / stats / config /
  plugins / memory / prompts / files / news / adapter / reasoning / market / learning。
- 结果：全部渲染成功，无崩溃；资讯/适配器/学习等页在真实接口下正常（适配器当前未设路径、学习空输入时按钮禁用，符合预期）。
- 结论：菜单内 18 个页面均为真实 SwiftUI 实现（无占位），仅余逐项像素/动画微调。

## 12. 最终逐页截图核验（19 页，真实数据）

- artifact：13652318964（home/manage/chat/room/logs/settings/bots/dark/stats/config/plugins/memory/prompts/files/news/adapter/reasoning/market/learning）。
- 已验证有真实数据：日志（已连接，200+ 条，ERROR/WARN 着色）、聊天室（真实对话）、统计（图表）、插件（21 项+开关）、文件（12 项）、长期记忆（125 条）、提示词（57 条）、资讯、插件市场（427 条，显示 200）。
- 适配器：服务端未设置配置文件路径，页面正确显示引导与网页版入口。
- 学习：表达/黑话抽取页可用（需粘贴文本后点“抽取候选”）。
- 麦麦设置为只读 JSON 树，默认展开前两层；日志筛选/来源 chip 不再竖排换行。
- CI 截图步骤 timeout 已由 15 分钟提高到 30 分钟（首次启动约 8.5 分钟，19 页约 16 分钟）。

## 13. 第二次核验（artifact 13653042291）

- 19 页再次全量截图成功；新增/修复：
  - 适配器设置：可**填写/修改配置文件路径**（POST config/adapter-config/path），保存后自动读取内容；
  - 麦麦设置：新增**配置项搜索**（跨层键名/值匹配，最多 200 条）；
  - 推理过程：从 JSON 树改为**阶段/文件可读列表**（会话数、最近时间）；
  - 日志：来源/筛选 chip 不再竖排换行；
  - 记忆：person_fact 显示「人物事实 · 短ID」。
- 仍为只读（有意保守，避免误改生产）：麦麦设置、插件市场安装、推理详情、聊天流时间线、学习候选入库。
- CI 截图步骤 timeout 30 分钟；GM_TEST_COOKIE 由仓库 owner 维护。

## 14. 三级页面扩展（当前会话）

新增并已接入管理菜单（多数已真实数据截图验证）：
- 资源：表情(1987)/表达方式(8992)/黑话(6963)/人物(501) —— 服务端搜索+分页；
- 聊天管理（会话详情：暂停回复、发言频率）、监控（active-context）、观察（概览+最近活动）；
- Agent 设置 / 电脑使用 / MCP 设置（config section）；
- 知识图谱（节点/关系，1617/270）、模型预设（任务→模型）、数据迁移（导入任务/参数）、帮助历史、设置组件；
- 插件详情 Sheet（plugins/config/{id}）；「长期记忆」重命名为「知识库」。

截图 artifact：13653693310（表情/表达/黑话/人物/聊天管理）、13655053960（Agent/知识图谱）、
13656583334（模型预设/数据迁移）、13657676775（监控/设置组件）、13659211892（观察）。

## 15. 插件扩展与回归（artifact 合集）

- 插件扩展注册表页 + 声明式渲染器（stack/card/grid/collapsible/text/stat/progress/table/input/switch/select/button）；
  queries/actions 调用 /plugins/runtime/webui/{plugin}/{page}/{kind}/{name}；示例「生活频率」页真实渲染成功（artifact 13662416287）。
- custom 模式插件页：拉取 /document HTML 用 WKWebView 渲染。
- 全量回归截图：13659518439、13663751347（19 tab，无回归）。
- 测试钩子 TestSupport.effectiveTab 仅用于截图重映射。

## 16. 动画与交互对齐（本会话后段）

- Tab 切换：弹簧 stiffness 420 / damping 36；内容切换 0.26s cubic-bezier(.22,1,.36,1) 淡入淡出（respecting reduce-motion）。
- 按压反馈：首页宫格、管理菜单行、聊天列表行使用 PressableStyle（0.12s ease-out 缩放/透明度）。
- 触感：底部 Tab 与搜索按钮加 UIImpactFeedbackGenerator(.soft)。
- 回归截图：13664108646（19 tab，动画改动无副作用）。

## 17. 资源/插件写能力

- 表情详情：注册 / 禁用 / 删除（emoji/{id}/register、/ban、DELETE）。
- 表达/黑话：新增（全局，POST expression/ 、jargon/）、删除（DELETE /{id}）。
- 插件详情：配置 / 原始 / Schema 三视图。
- 聊天管理：私聊暂停回复开关、发言频率展示。
- 适配器：可设置/修改配置文件路径。
