//
//  ChatClient.swift
//  MaiBot
//
//  Native chat over the bot unified websocket. Like LogsClient, it probes the
//  bot proxy path first (needs panel session, present on device after WebView
//  login) then the plain path, keeping whichever acknowledges session.open.
//
//    -> {"op":"call","id","domain":"chat","method":"session.open"|"message.send","session":<id>,"data":{...}}
//    <- {"op":"response",...}
//    <- {"op":"event","domain":"chat","event":<type>,"data":{...}}
//  Chat event types: session_info / history / system / user_message / typing /
//  bot_message (the bot reply) / error.
//

import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    var sender: String = ""
    var time: String = ""
    enum Role { case user, bot, system }
}

@MainActor
@Observable
final class ChatClient {
    enum Status: Equatable { case idle, connecting, ready; case failed(String) }

    var status: Status = .idle
    var messages: [ChatMessage] = []
    var waiting = false
    var peerName = "麦麦"
    private(set) var debug = ""

    private var task: URLSessionWebSocketTask?
    private let sessionID = UUID().uuidString
    private var rpc = 0
    private let client: APIClient
    private var ping: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var botID: String?

    init(client: APIClient) { self.client = client }

    private func url(for path: String) -> URL? {
        guard var comp = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        comp.scheme = (client.baseURL.scheme == "https") ? "wss" : "ws"
        comp.path = path
        comp.query = nil
        return comp.url
    }

    private func candidatePaths() -> [String] {
        var paths: [String] = []
        if let id = botID, !id.isEmpty { paths.append("/api/host/bots/\(id)/proxy/api/webui/ws") }
        paths.append("/api/webui/ws")
        return paths
    }

    func connect() async {
        if case .ready = status { return }
        if case .connecting = status { return }
        status = .connecting
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self else { return }
            await MainActor.run { if case .connecting = self.status { self.status = .failed("连接超时") } }
        }
        let mode = try? await client.hostMode()
        botID = mode?.selectedBotID

        for path in candidatePaths() {
            guard let u = url(for: path) else { continue }
            var req = URLRequest(url: u)
            var cookies: [String] = []
            if let s = client.sessionCookie, !s.isEmpty { cookies.append(s) }
            if let pc = client.panelCookie, !pc.isEmpty { cookies.append(pc) }
            if !cookies.isEmpty { req.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie") }

            let t = URLSession.shared.webSocketTask(with: req)
            t.resume()
            sendRaw(t, ["op": "call", "id": nextID(), "domain": "chat", "method": "session.open",
                        "session": sessionID, "data": ["user_name": "我"]])

            if let first = await firstMessage(t, timeout: 3.0) {
                task = t
                watchdog?.cancel()
                status = .ready
                debug = (path.contains("/proxy/") ? "代理" : "顶层")
                handle(first)
                startListen(t)
                startPing(t)
                return
            }
            t.cancel(with: .goingAway, reason: nil)
        }
        status = .failed("无法连接聊天（缺少面板会话）")
    }

    private func firstMessage(_ t: URLSessionWebSocketTask, timeout: Double) async -> URLSessionWebSocketTask.Message? {
        await withTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask { do { return try await t.receive() } catch { return nil } }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func nextID() -> String { rpc += 1; return "c\(rpc)" }
    private func sendRaw(_ t: URLSessionWebSocketTask, _ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        t.send(.string(s)) { _ in }
    }
    private func sendRaw(_ obj: [String: Any]) {
        guard let t = task else { return }
        sendRaw(t, obj)
    }

    private func startListen(_ t: URLSessionWebSocketTask) {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let msg = try await t.receive()
                    await MainActor.run { self?.handle(msg) }
                } catch {
                    await MainActor.run { self?.status = .failed("连接中断"); self?.waiting = false }
                    break
                }
            }
        }
    }

    private func startPing(_ t: URLSessionWebSocketTask) {
        ping?.cancel()
        ping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self else { return }
                await MainActor.run { self.sendRaw(t, ["op": "ping"]) }
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        var text: String?
        switch msg {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let s = text, let d = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }

        let op = obj["op"] as? String ?? ""
        if op == "pong" { return }
        if op == "response" {
            if (obj["ok"] as? Bool) == false {
                let err = obj["error"] as? [String: Any]
                let m = (err?["message"] as? String) ?? "请求失败"
                messages.append(ChatMessage(role: .system, text: "[错误] " + m))
                waiting = false
            }
            return
        }
        guard op == "event", (obj["domain"] as? String) == "chat" else { return }
        let data = obj["data"] as? [String: Any] ?? [:]
        let type = (data["type"] as? String) ?? (obj["event"] as? String) ?? ""

        switch type {
        case "session_info":
            if let n = (data["bot_name"] as? String) ?? ((data["bot"] as? [String: Any])?["name"] as? String), !n.isEmpty {
                peerName = n
            }
        case "bot_message":
            let t = richText(data)
            if !t.isEmpty { messages.append(ChatMessage(role: .bot, text: t, sender: senderName(data, fallback: "麦麦"), time: shortTime(data))) }
            waiting = false
        case "user_message":
            if isOwnEcho(data) { return }
            let t = richText(data)
            if !t.isEmpty { messages.append(ChatMessage(role: .user, text: t, sender: senderName(data, fallback: "我"), time: shortTime(data))) }
        case "typing":
            waiting = (data["is_typing"] as? Bool) ?? false
        case "history":
            loadHistory(data)
        case "system":
            let c = richText(data)
            if !c.isEmpty { messages.append(ChatMessage(role: .system, text: c)) }
        case "error":
            let c = richText(data)
            messages.append(ChatMessage(role: .system, text: "[错误] " + (c.isEmpty ? "处理失败" : c)))
            waiting = false
        default:
            break
        }
    }

    private func isOwnEcho(_ data: [String: Any]) -> Bool {
        guard let origin = data["origin"] as? String else { return false }
        return origin.hasSuffix(":" + sessionID)
    }

    private func loadHistory(_ data: [String: Any]) {
        guard let arr = data["messages"] as? [[String: Any]] else { return }
        guard messages.isEmpty else { return }
        var out: [ChatMessage] = []
        for m in arr {
            let isBot = (m["is_bot"] as? Bool) ?? ((m["type"] as? String) == "bot")
            let t = richText(m)
            if t.isEmpty { continue }
            let name = (m["sender_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (isBot ? "麦麦" : "我")
            out.append(ChatMessage(role: isBot ? .bot : .user, text: t, sender: name, time: shortTime(m)))
        }
        if !out.isEmpty { messages = out }
    }

    private func senderName(_ d: [String: Any], fallback: String) -> String {
        if let s = d["sender"] as? [String: Any], let n = s["name"] as? String, !n.isEmpty { return n }
        return fallback
    }
    private func shortTime(_ d: [String: Any]) -> String {
        if let ts = d["timestamp"] as? Double, ts > 0 {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: Date(timeIntervalSince1970: ts))
        }
        if let s = d["timestamp"] as? String, s.count >= 5 { return String(s.suffix(5)) }
        return ""
    }

    private func richText(_ d: [String: Any]) -> String {
        if let c = d["content"] as? String, !c.isEmpty { return c }
        guard let segs = d["segments"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for seg in segs {
            let t = seg["type"] as? String ?? ""
            switch t {
            case "text": if let s = seg["data"] as? String { parts.append(s) }
            case "image": parts.append("[图片]")
            case "emoji": parts.append("[表情]")
            case "voice": parts.append("[语音]")
            case "file":  parts.append("[文件]")
            default: break
            }
        }
        return parts.joined()
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: t))
        waiting = true
        sendRaw(["op": "call", "id": nextID(), "domain": "chat", "method": "message.send",
                 "session": sessionID, "data": ["content": t, "user_name": "我"]])
    }

    func disconnect() {
        ping?.cancel(); listenTask?.cancel()
        sendRaw(["op": "call", "id": nextID(), "domain": "chat", "method": "session.close", "session": sessionID])
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil; status = .idle; waiting = false
    }
}
