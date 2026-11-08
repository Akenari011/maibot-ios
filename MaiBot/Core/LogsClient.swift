//
//  LogsClient.swift
//  MaiBot
//
//  Real-time logs over the bot's unified websocket. The public host does not
//  serve /api/webui/ws directly (403 even with a host session); the working
//  endpoint on the host origin is the bot proxy path. We therefore probe, in
//  order, the proxy path (needs panel session cookie — present on real device
//  after WebView login) and the plain path, and keep whichever acknowledges the
//  logs subscription within a short timeout.
//
//    -> {"op":"subscribe","id","domain":"logs","topic":"main","data":{"replay":200}}
//    <- {"op":"response","ok":true,...}
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
    enum Status: Equatable { case idle, connecting, ready; case failed(String) }

    var status: Status = .idle
    var entries: [LogEntry] = []
    private(set) var debug = ""

    private let maxEntries = 600
    private var task: URLSessionWebSocketTask?
    private var rpc = 0
    private let client: APIClient
    private var ping: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
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
        if let id = botID, !id.isEmpty {
            paths.append("/api/host/bots/\(id)/proxy/api/webui/ws")
        }
        paths.append("/api/webui/ws")
        return paths
    }

    func connect() async {
        if case .ready = status { return }
        if case .connecting = status { return }
        status = .connecting
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
            sendRaw(t, ["op": "subscribe", "id": nextID(), "domain": "logs", "topic": "main",
                        "data": ["replay": 200]])

            // Probe: wait up to 3s for the first frame (ack or snapshot).
            if let first = await firstMessage(t, timeout: 3.0) {
                task = t
                status = .ready
                debug = "通道 " + (path.contains("/proxy/") ? "代理" : "顶层")
                handle(first)
                startListen(t)
                startPing(t)
                return
            }
            t.cancel(with: .goingAway, reason: nil)
        }
        status = .failed("无法订阅日志（缺少面板会话）")
        debug = "两条通道均无响应"
    }

    private func firstMessage(_ t: URLSessionWebSocketTask, timeout: Double) async -> URLSessionWebSocketTask.Message? {
        await withTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask {
                do { return try await t.receive() } catch { return nil }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func nextID() -> String { rpc += 1; return "l\(rpc)" }

    private func sendRaw(_ t: URLSessionWebSocketTask, _ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        t.send(.string(s)) { _ in }
    }

    private func startListen(_ t: URLSessionWebSocketTask) {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let msg = try await t.receive()
                    await MainActor.run { self?.handle(msg) }
                } catch {
                    await MainActor.run { self?.status = .failed("连接中断") }
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
            let ok = (obj["ok"] as? Bool) ?? false
            if !ok {
                let err = obj["error"] as? [String: Any]
                status = .failed((err?["message"] as? String) ?? "日志订阅失败")
                debug = "订阅失败"
            } else if !debug.contains("快照") {
                debug = "订阅已确认"
            }
            return
        }
        guard op == "event", (obj["domain"] as? String) == "logs" else { return }
        let event = obj["event"] as? String ?? ""
        let data = obj["data"] as? [String: Any] ?? [:]

        if event == "snapshot" {
            guard let arr = data["entries"] as? [[String: Any]] else { debug = "快照无 entries"; return }
            let list = decode(arr)
            entries = list
            debug = "快照 \(arr.count)/解析 \(list.count)"
        } else if event == "entry" {
            guard let e = data["entry"] as? [String: Any] else { return }
            append(decode([e]))
            if entries.count == 1 { debug = "实时首条" }
        }
    }

    private func decode(_ arr: [[String: Any]]) -> [LogEntry] {
        arr.compactMap { d -> LogEntry? in
            guard let id = d["id"] as? String, let ts = d["timestamp"] as? String,
                  let level = d["level"] as? String, let module = d["module"] as? String,
                  let message = d["message"] as? String else { return nil }
            return LogEntry(id: id, timestamp: ts, level: level, module: module, message: message,
                            moduleColor: d["moduleColor"] as? String,
                            moduleBold: d["moduleBold"] as? Bool,
                            moduleDisplayName: d["moduleDisplayName"] as? String)
        }
    }

    private func append(_ new: [LogEntry]) {
        guard !new.isEmpty else { return }
        var seen = Set(entries.map { $0.id })
        for e in new where !seen.contains(e.id) { entries.append(e); seen.insert(e.id) }
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    func clear() { entries.removeAll() }

    func disconnect() {
        ping?.cancel(); listenTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil; status = .idle
    }
}
