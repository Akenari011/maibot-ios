//
//  ChatClient.swift
//  MaiBot
//
//  Native chat over the panel websocket (/api/webui/ws).
//  Protocol: {op:"call", id, domain:"chat", method:"session.open"|"message.send", session, data}
//  Replies arrive as {op:"event", domain:"chat", event, data:{content}}.
//

import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role { case user, bot }
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
        if let pc = client.panelCookie { cookies.append(pc) }
        if !cookies.isEmpty { req.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie") }

        let t = URLSession.shared.webSocketTask(with: req)
        task = t
        t.resume()
        status = .ready
        sendRaw(["op": "call", "id": nextID(), "domain": "chat", "method": "session.open", "session": sessionID])
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

        if (obj["op"] as? String) == "event" {
            let data = obj["data"] as? [String: Any] ?? [:]
            let ev = (obj["event"] as? String) ?? ""
            let content = (data["content"] as? String)
                ?? (data["text"] as? String)
                ?? (data["message"] as? String)
                ?? ""
            if !content.isEmpty { appendBot(content) }
            if ev.contains("end") || ev.contains("done") || ev.contains("complete") { waiting = false }
        } else if (obj["op"] as? String) == "response" {
            if (obj["ok"] as? Bool) == false {
                let err = obj["error"] as? [String: Any]
                let m = (err?["message"] as? String) ?? "请求失败"
                messages.append(ChatMessage(role: .bot, text: "[错误] " + m))
                waiting = false
            }
        }
    }

    private func appendBot(_ content: String) {
        if waiting, let last = messages.last, last.role == .bot {
            messages[messages.count - 1].text += content
        } else {
            messages.append(ChatMessage(role: .bot, text: content))
        }
        waiting = true
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
    }
}