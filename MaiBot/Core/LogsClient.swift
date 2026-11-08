//
//  LogsClient.swift
//  MaiBot
//
//  Real-time logs over the same unified panel websocket (/api/webui/ws).
//  The browser panel does NOT use a separate /ws/logs endpoint for the log
//  page; it subscribes on the unified socket:
//    -> {"op":"subscribe","id","domain":"logs","topic":"main","data":{"replay":100}}
//    <- {"op":"response","ok":true,"data":{"domain":"logs","topic":"main"}}
//    <- {"op":"event","domain":"logs","event":"snapshot","data":{"entries":[...]}}
//    <- {"op":"event","domain":"logs","event":"entry","data":{"entry":{...}}}
//

import Foundation
import Observation

struct LogEntry: Identifiable, Decodable, Equatable {
    let id: String
    let timestamp: String
    let level: String
    let module: String
    let message: String
    var moduleColor: String?
    var moduleBold: Bool?
    var moduleDisplayName: String?

    /// "HH:MM:SS" pulled out of the panel timestamp.
    var clock: String {
        if let last = timestamp.split(separator: " ").last, last.count >= 8 {
            return String(last.prefix(8))
        }
        return timestamp
    }
}

@MainActor
@Observable
final class LogsClient {
    enum Status: Equatable {
        case idle, connecting, ready
        case failed(String)
    }

    var status: Status = .idle
    var entries: [LogEntry] = []

    private let maxEntries = 600
    private var task: URLSessionWebSocketTask?
    private var rpc = 0
    private let client: APIClient
    private var ping: Task<Void, Never>?
    private let decoder = JSONDecoder()

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
        sendRaw(["op": "subscribe", "id": nextID(), "domain": "logs", "topic": "main",
                 "data": ["replay": 200]])
        listen()
        startPing()
    }

    private func nextID() -> String { rpc += 1; return "l\(rpc)" }

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

        let op = obj["op"] as? String ?? ""
        if op == "response" {
            if (obj["ok"] as? Bool) == false {
                let err = obj["error"] as? [String: Any]
                status = .failed((err?["message"] as? String) ?? "日志订阅失败")
            }
            return
        }
        guard op == "event", (obj["domain"] as? String) == "logs" else { return }
        let event = obj["event"] as? String ?? ""
        let data = obj["data"] as? [String: Any] ?? [:]

        if event == "snapshot" {
            guard let arr = data["entries"] as? [[String: Any]] else { return }
            entries = decode(arr)
        } else if event == "entry" {
            guard let e = data["entry"] as? [String: Any] else { return }
            append(decode([e]))
        }
    }

    private func decode(_ arr: [[String: Any]]) -> [LogEntry] {
        guard let d = try? JSONSerialization.data(withJSONObject: arr),
              let list = try? decoder.decode([LogEntry].self, from: d) else { return [] }
        return list
    }

    private func append(_ new: [LogEntry]) {
        guard !new.isEmpty else { return }
        var seen = Set(entries.map { $0.id })
        for e in new where !seen.contains(e.id) {
            entries.append(e)
            seen.insert(e.id)
        }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() { entries.removeAll() }

    func disconnect() {
        ping?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        status = .idle
    }
}
