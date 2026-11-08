//
//  ChatClient.swift
//  MaiBot
//
//  Native chat over the panel websocket (/api/webui/ws).
//
//  Protocol, verified against the panel's unified.py / service.py:
//    -> {"op":"call","id","domain":"chat","method":"session.open"|"message.send","session":<id>,"data":{...}}
//    <- {"op":"response","id","ok",...}
//    <- {"op":"event","domain":"chat","event":<type>,"data":{...}}
//
//  Chat event types:
//    session_info       -- metadata only, ignored
//    history            -- data.messages: [{type:"bot"|"user", content, segments?}]
//    system             -- data.content: welcome / info line
//    user_message       -- someone's message; ours echoes back too (data.origin)
//    typing             -- data.is_typing
//    bot_message        -- THE bot reply; data.content (+ data.segments for rich)
//    error              -- data.content
//

import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role { case user, bot, system }
}

@MainActor
@Observable
final class ChatClient {
    enum Status: Equatable {
        case idle, connecting, ready
        case failed(String)
    }

    var status: Status = .idle
    var messages: [ChatMessage] = []
    var waiting = false

    private var task: URLSessionWebSocketTask?
    private let sessionID = UUID().uuidString
    private var rpc = 0
    private let client: APIClient
    private var ping: Task<Void, Never>?

    init(client: APIClient) { self.client = client }

    private func wsURL() -> URL? {
        guard var comp = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        comp.scheme = (client.baseURL.scheme == "https") ? "wss" : "ws"
        comp.path = "/api/webui/ws"
        comp.query = nil
        return comp.url
    }

    func connect() async {
        if case .ready = status { return }
        if case .connecting = status { return }
        status = .connecting
        // A plain API call mints the panel cookie we need for the handshake.
        _ = try? await client.hostMode()
        guard let url = wsURL() else { status = .failed("无效地址"); return }

        var req = URLRequest(url: url)
        var cookies: [String] = []
        if let s = client.sessionCookie, !s.isEmpty { cookies.append(s) }
        if let pc = client.panelCookie, !pc.isEmpty { cookies.append(pc) }
        if !cookies.isEmpty { req.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie") }

        let t = URLSession.shared.webSocketTask(with: req)
        task = t
        t.resume()
        status = .ready
        sendRaw(["op": "call", "id": nextID(), "domain": "chat", "method": "session.open",
                 "session": sessionID, "data": ["user_name": "我"]])
        listen()
        startPing()
    }

    private func nextID() -> String { rpc += 1; return "c\(rpc)" }

    private func sendRaw(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func startPing() {
        ping?.cancel()
        ping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                self?.sendRaw(["op": "ping"])
            }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let msg):
                    self.handle(msg)
                    self.listen()
                case .failure(let e):
                    self.status = .failed(e.localizedDescription)
                    self.waiting = false
                }
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
        case "bot_message":
            let t = richText(data)
            if !t.isEmpty { messages.append(ChatMessage(role: .bot, text: t)) }
            waiting = false
        case "user_message":
            // Echo. Our own send already appended the bubble locally; the
            // server stamps origin with the internal session id which ends in
            // our client session id, so we can recognise and skip it. Messages
            // from other clients (different origin) are shown.
            if isOwnEcho(data) { return }
            let t = richText(data)
            if !t.isEmpty { messages.append(ChatMessage(role: .user, text: t)) }
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
        guard messages.isEmpty else { return }   // don't clobber live messages on reconnect
        var out: [ChatMessage] = []
        for m in arr {
            let isBot = (m["is_bot"] as? Bool) ?? ((m["type"] as? String) == "bot")
            let t = richText(m)
            if t.isEmpty { continue }
            out.append(ChatMessage(role: isBot ? .bot : .user, text: t))
        }
        if !out.isEmpty { messages = out }
    }

    /// Pull plain text from a chat payload: prefer "content", otherwise
    /// concatenate "segments" (text kept, media replaced by a short tag).
    private func richText(_ d: [String: Any]) -> String {
        if let c = d["content"] as? String, !c.isEmpty { return c }
        guard let segs = d["segments"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for seg in segs {
            let t = seg["type"] as? String ?? ""
            switch t {
            case "text":
                if let s = seg["data"] as? String { parts.append(s) }
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
        ping?.cancel()
        sendRaw(["op": "call", "id": nextID(), "domain": "chat", "method": "session.close", "session": sessionID])
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        status = .idle
        waiting = false
    }
}
