//
//  APIClient.swift
//  MaiBot
//
//  Thin async wrapper over the host JSON API.
//
//  Two details that are easy to get wrong:
//
//  1. Writes to /api/host/* require the header "X-MaiBot-Host: 1". The server
//     rejects them with 403 "缺少管理请求标识" otherwise.
//  2. The server's CSRF check (same_webui_origin) short-circuits to true when
//     the Origin header is absent — which URLSession never sets. So we must
//     NOT add an Origin header, or the check starts comparing it to Host.
//

import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "登录已失效，请重新登录"
        case let .http(code, body):
            return body.isEmpty ? "请求失败（HTTP \(code)）" : body
        case let .transport(e):
            return e.localizedDescription
        case let .decoding(e):
            return "响应解析失败：\(e.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class APIClient {
    /// Persisted so a user on a self-hosted instance can point the app at their
    /// own host without a rebuild.
    var baseURL: URL {
        didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.baseKey) }
    }

    /// The panel session cookie value, captured from the login web view.
    var sessionCookie: String?

    private static let baseKey = "maibot.baseURL"
    private let session: URLSession

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.baseKey)
        baseURL = URL(string: saved ?? "https://maibot.galmaster.online")!

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.httpShouldSetCookies = false      // we attach the cookie ourselves
        cfg.httpCookieAcceptPolicy = .never
        cfg.waitsForConnectivity = true
        session = URLSession(configuration: cfg)
    }

    // MARK: - Core plumbing

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.http(0, "无效的地址")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        if let sessionCookie, !sessionCookie.isEmpty {
            req.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        // Writes to /api/host/* are gated on this marker header.
        if method != "GET" && method != "HEAD" && path.hasPrefix("/api/host/") {
            req.setValue("1", forHTTPHeaderField: "X-MaiBot-Host")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.http(0, "无响应")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.display
                ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, msg)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(try makeRequest(path))
    }

    @discardableResult
    private func post(_ path: String, json: [String: Any] = [:]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json)
        let req = try makeRequest(path, method: "POST", body: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0, "无响应") }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.display
                ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    // MARK: - Endpoints

    func checkAuth() async throws -> Bool {
        struct R: Codable { let authenticated: Bool }
        let r: R = try await get("/api/webui/auth/check")
        return r.authenticated
    }

    func hostMode() async throws -> HostMode {
        try await get("/api/host/mode")
    }

    func bots() async throws -> [Bot] {
        let list: BotList = try await get("/api/host/bots")
        return list.bots
    }

    func settings() async throws -> HostSettings {
        try await get("/api/host/settings")
    }

    /// Start / stop / restart. The host API expresses this as a POST of the
    /// desired state onto the bot resource.
    func setBotState(_ botID: String, action: BotAction) async throws {
        try await post("/api/host/bots/\(botID)", json: ["action": action.rawValue])
    }

    func selectBot(_ botID: String) async throws {
        try await post("/api/host/selection", json: ["bot_id": botID])
    }

    func logs(botID: String, limit: Int = 400) async throws -> String {
        // The log endpoint is versioned; try the modern shape then fall back.
        for path in [
            "/api/host/bots/\(botID)/logs?limit=\(limit)",
            "/api/host/logs?bot_id=\(botID)&limit=\(limit)"
        ] {
            if let chunk: LogChunk = try? await get(path) {
                let text = chunk.text
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    func logout() async throws {
        try await post("/api/webui/auth/logout")
    }
}

enum BotAction: String {
    case start, stop, restart
}
