//
//  APIClient.swift
//  MaiBot
//
//  Writes to /api/host/* need "X-MaiBot-Host: 1". The server CSRF check
//  short-circuits when Origin is absent, and URLSession never sets it, so we
//  must not add one.
//

import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录已失效，请重新登录"
        case let .http(code, body): return body.isEmpty ? "请求失败（HTTP \(code)）" : body
        case let .transport(e): return e.localizedDescription
        case let .decoding(e): return "响应解析失败：\(e.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class APIClient {
    var baseURL: URL {
        didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.baseKey) }
    }
    var sessionCookie: String?
    /// The panel's own session (maibot_host_session_*), minted by the gateway on
    /// an API response. Needed for the websocket handshake.
    var panelCookie: String?

    private static let baseKey = "maibot.baseURL"
    private let session: URLSession

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.baseKey)
        baseURL = URL(string: saved ?? "https://maibot.galmaster.online")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.waitsForConnectivity = true
        session = URLSession(configuration: cfg)
    }

    /// A 401 from a bot-proxy endpoint usually means that bot's own WebUI session
    /// is missing (the host session is still valid), so we must not sign out.
    private func unauthorizedError(for path: String) -> APIError {
        path.contains("/proxy/")
            ? .http(401, "机器人会话未就绪，请先在网页版打开该机器人后重试")
            : .unauthorized
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.http(0, "无效的地址")
        }
        var req = URLRequest(url: url)
        if let timeout { req.timeoutInterval = timeout }
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        if let sessionCookie, !sessionCookie.isEmpty {
            req.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        if method != "GET" && method != "HEAD" && path.hasPrefix("/api/host/") {
            req.setValue("1", forHTTPHeaderField: "X-MaiBot-Host")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw APIError.transport(error) }
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        capturePanel(http)
        if http.statusCode == 401 { throw unauthorizedError(for: req.url?.path ?? "") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.display
                ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, msg)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func capturePanel(_ http: HTTPURLResponse) {
        for (k, v) in http.allHeaderFields {
            guard String(describing: k).lowercased() == "set-cookie" else { continue }
            let raw = String(describing: v)
            for part in raw.components(separatedBy: ",") {
                let first = part.split(separator: ";").first.map(String.init) ?? part
                let t = first.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(APIClient.panelPrefix) {
                    panelCookie = t
                }
            }
        }
    }

    static let panelPrefix = "maibot_host_session_*"

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(try makeRequest(path))
    }

    @discardableResult
    private func sendJSON(_ method: String, _ path: String, _ json: [String: Any]?) async throws -> Data {
        let body = json.map { try? JSONSerialization.data(withJSONObject: $0) } ?? nil
        let req = try makeRequest(path, method: method, body: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        capturePanel(http)
        if http.statusCode == 401 { throw unauthorizedError(for: path) }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.display
                ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    @discardableResult
    private func post(_ path: String, json: [String: Any] = [:]) async throws -> Data {
        try await sendJSON("POST", path, json)
    }

    // MARK: - Host endpoints

    func checkAuth() async throws -> Bool {
        struct R: Codable { let authenticated: Bool }
        let r: R = try await get("/api/webui/auth/check")
        return r.authenticated
    }

    func hostMode() async throws -> HostMode { try await get("/api/host/mode") }

    func bots() async throws -> [Bot] {
        let list: BotList = try await get("/api/host/bots")
        return list.bots
    }

    func setBotState(_ botID: String, action: BotAction) async throws {
        try await post("/api/host/bots/\(botID)", json: ["action": action.rawValue])
    }

    func selectBot(_ botID: String) async throws {
        try await post("/api/host/selection", json: ["bot_id": botID])
    }

    func createBot(name: String) async throws {
        try await post("/api/host/bots", json: ["name": name])
    }

    func cloneBot(_ botID: String, name: String) async throws {
        try await post("/api/host/bots/\(botID)/clone", json: ["name": name])
    }

    func renameBot(_ botID: String, name: String) async throws {
        try await sendJSON("PATCH", "/api/host/bots/\(botID)", ["name": name])
    }

    func deleteBot(_ botID: String) async throws {
        try await sendJSON("DELETE", "/api/host/bots/\(botID)", nil)
    }

    // MARK: - Per-bot proxy (the panel itself lives behind /proxy)

    private func proxy(_ botID: String, _ sub: String) -> String {
        "/api/host/bots/\(botID)/proxy/api/webui/\(sub)"
    }

    func dashboard(botID: String, hours: Int = 24) async throws -> Dashboard {
        try await get(proxy(botID, "statistics/dashboard?hours=\(hours)"))
    }

    func localCache(botID: String) async throws -> LocalCache {
        try await get(proxy(botID, "system/local-cache"))
    }

    func news(botID: String) async throws -> [NewsResponse.NewsItem] {
        let r: NewsResponse = try await get(proxy(botID, "news"))
        return r.items
    }

    func getRaw(_ path: String, timeout: TimeInterval? = nil) async throws -> Any {
        let req = try makeRequest(path, timeout: timeout)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        capturePanel(http)
        if http.statusCode == 401 { throw unauthorizedError(for: path) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    func pluginsInstalled(botID: String) async throws -> Any { try await getRaw(proxy(botID, "plugins/installed")) }
    func configPrompts(botID: String) async throws -> Any { try await getRaw(proxy(botID, "config/prompts")) }
    func adapterConfigPath(botID: String) async throws -> Any { try await getRaw(proxy(botID, "config/adapter-config/path")) }
    func reasoningStages(botID: String) async throws -> Any { try await getRaw(proxy(botID, "reasoning-process/stages")) }
    func reasoningFiles(botID: String) async throws -> Any { try await getRaw(proxy(botID, "reasoning-process/files")) }
    func marketplace(botID: String) async throws -> Any { try await getRaw(proxy(botID, "plugins/marketplace"), timeout: 60) }
    func pluginWebUI(botID: String) async throws -> Any { try await getRaw(proxy(botID, "plugins/runtime/webui")) }
    func pluginDocumentText(botID: String, pluginID: String, pageID: String) async throws -> String {
        let p = [pluginID, pageID].map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }.joined(separator: "/")
        let req = try makeRequest(proxy(botID, "plugins/runtime/webui/\(p)/document"))
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        if http.statusCode == 401 { throw unauthorizedError(for: req.url?.path ?? "") }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode, "") }
        return String(data: data, encoding: .utf8) ?? ""
    }
    func pluginInvoke(botID: String, pluginID: String, pageID: String, kind: String, name: String, args: [String: Any]) async throws -> Any {
        let p = [pluginID, pageID, kind, name].map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }.joined(separator: "/")
        let data = try await sendJSON("POST", proxy(botID, "plugins/runtime/webui/\(p)"), ["args": args, "confirmed": false])
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return obj["result"] ?? obj
    }

    func pluginRaw(botID: String, pluginID: String) async throws -> Any {
        let enc = pluginID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pluginID
        return try await getRaw(proxy(botID, "plugins/config/\(enc)/raw"))
    }
    func pluginSchema(botID: String, pluginID: String) async throws -> Any {
        let enc = pluginID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pluginID
        return try await getRaw(proxy(botID, "plugins/config/\(enc)/schema"))
    }

    func pluginConfig(botID: String, pluginID: String) async throws -> Any {
        let enc = pluginID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pluginID
        return try await getRaw(proxy(botID, "plugins/config/\(enc)"))
    }

    func togglePlugin(botID: String, pluginID: String) async throws -> Any {
        let enc = pluginID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pluginID
        let data = try await sendJSON("POST", proxy(botID, "plugins/config/\(enc)/toggle"), nil)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
    func learnText(botID: String, kind: String, text: String) async throws -> Any {
        let req = try makeRequest(proxy(botID, "learning/text/extract"), method: "POST",
                                  body: try JSONSerialization.data(withJSONObject: ["kind": kind, "text": text]),
                                  timeout: 180)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        capturePanel(http)
        if http.statusCode == 401 { throw unauthorizedError(for: req.url?.path ?? "") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
    func chatSessionDetail(botID: String, sessionID: String) async throws -> Any {
        let enc = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID
        return try await getRaw(proxy(botID, "chat/sessions/\(enc)"))
    }

    func setPrivateReplyPause(botID: String, sessionID: String, paused: Bool) async throws -> Any {
        let enc = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID
        let data = try await sendJSON("PUT", proxy(botID, "chat/sessions/\(enc)/private-reply-pause"), ["paused": paused])
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    func resourceCreate(botID: String, path: String, body: [String: Any]) async throws -> Any {
        let basePath = path.replacingOccurrences(of: "/list", with: "")
        let data = try await sendJSON("POST", proxy(botID, basePath + "/"), body)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    func resourceDelete(botID: String, path: String, id: String) async throws -> Any {
        let basePath = path.replacingOccurrences(of: "/list", with: "")
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await sendJSON("DELETE", proxy(botID, "\(basePath)/\(enc)"), nil)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    func getData(_ path: String) async throws -> Data {
        let req = try makeRequest(path)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        if http.statusCode == 401 { throw unauthorizedError(for: req.url?.path ?? "") }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode, "") }
        return data
    }
    func emojiThumbnail(botID: String, id: String) async throws -> Data {
        for _ in 0..<8 {
            let d = try await getData(proxy(botID, "emoji/\(id)/thumbnail"))
            if let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], obj["status"] != nil {
                try? await Task.sleep(for: .milliseconds(700))
                continue
            }
            return d
        }
        return Data()
    }

    func emojiRegister(botID: String, id: String) async throws -> Any {
        let data = try await sendJSON("POST", proxy(botID, "emoji/\(id)/register"), nil)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
    func emojiBan(botID: String, id: String) async throws -> Any {
        let data = try await sendJSON("POST", proxy(botID, "emoji/\(id)/ban"), nil)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }
    func emojiDelete(botID: String, id: String) async throws -> Any {
        let data = try await sendJSON("DELETE", proxy(botID, "emoji/\(id)"), nil)
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    func resourceDetail(botID: String, path: String, id: String) async throws -> Any {
        let basePath = path.replacingOccurrences(of: "/list", with: "")
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await getRaw(proxy(botID, "\(basePath)/\(enc)"))
    }

    func resourcePage(botID: String, path: String, page: Int, search: String) async throws -> Any {
        var q = "\(path)?page=\(page)&page_size=20"
        let s = search.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty, let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            q += "&search=\(enc)"
        }
        return try await getRaw(proxy(botID, q))
    }

    func saveAdapterConfigPath(botID: String, path: String) async throws -> Any {
        let data = try await sendJSON("POST", proxy(botID, "config/adapter-config/path"), ["path": path])
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    func adapterConfig(botID: String, path: String) async throws -> Any {
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return try await getRaw(proxy(botID, "config/adapter-config?path=\(enc)"))
    }
    func files(botID: String) async throws -> Any { try await getRaw(proxy(botID, "files")) }
    func memorySources(botID: String) async throws -> Any { try await getRaw(proxy(botID, "memory/sources")) }
    func importTasks(botID: String) async throws -> Any { try await getRaw(proxy(botID, "memory/import/tasks")) }
    func configModel(botID: String) async throws -> Any { try await getRaw(proxy(botID, "config/model")) }
    func helpSessions(botID: String) async throws -> Any { try await getRaw(proxy(botID, "search/help/sessions")) }
    func activeContext(botID: String, sessionID: String) async throws -> Any {
        let enc = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        return try await getRaw(proxy(botID, "reasoning-process/active-context?session_id=\(enc)"))
    }
    func memoryGraph(botID: String, limit: Int = 500) async throws -> Any {
        try await getRaw(proxy(botID, "memory/graph?limit=\(limit)"), timeout: 60)
    }

    func configBot(botID: String) async throws -> Any { try await getRaw(proxy(botID, "config/bot")) }

    func chatStreams(botID: String) async throws -> [ChatStream] {
        let r: ChatStreamList = try await get("/api/host/bots/\(botID)/proxy/api/chat/sessions?limit=1000")
        return r.sessions
    }

    func models(botID: String) async throws -> [ModelConfig.ModelInfo] {
        let r: ModelConfigResponse = try await get(proxy(botID, "config/model"))
        return r.config.models ?? []
    }

    func logout() async throws { try await post("/api/webui/auth/logout") }

    func updateToken(_ newToken: String) async throws {
        _ = try await sendJSON("POST", "/api/webui/auth/update", ["new_token": newToken])
    }

    func regenerateToken() async throws -> String {
        let data = try await sendJSON("POST", "/api/webui/auth/regenerate", [:])
        struct R: Decodable { let token: String }
        return (try? JSONDecoder().decode(R.self, from: data))?.token ?? ""
    }

    func resetSetup(resetPassword: Bool) async throws {
        try await post("/api/webui/setup/reset", json: ["reset_password": resetPassword])
    }
}

enum BotAction: String { case start, stop, restart }