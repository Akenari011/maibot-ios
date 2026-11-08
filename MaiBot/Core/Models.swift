//
//  Models.swift
//  MaiBot
//
//  Plain Codable mirrors of the host API. Field names match the JSON exactly;
//  anything the app does not use is simply omitted.
//

import Foundation

// MARK: - Bot

struct Bot: Codable, Identifiable, Hashable {
    let botID: String
    let name: String
    let directory: String?
    let owned: Bool?
    let createdAt: String?
    let initialization: String?
    let initializationError: String?
    let desiredState: String?
    let restartPolicy: String?
    let status: String?
    let detail: String?
    let pid: Int?
    let startedAt: String?
    let exitedAt: String?
    let exitCode: Int?
    let error: String?
    let retryAt: String?
    let logPath: String?

    var id: String { botID }

    enum CodingKeys: String, CodingKey {
        case botID = "bot_id"
        case name, directory, owned
        case createdAt = "created_at"
        case initialization
        case initializationError = "initialization_error"
        case desiredState = "desired_state"
        case restartPolicy = "restart_policy"
        case status, detail, pid
        case startedAt = "started_at"
        case exitedAt = "exited_at"
        case exitCode = "exit_code"
        case error
        case retryAt = "retry_at"
        case logPath = "log_path"
    }

    /// "running" / "stopped" / "starting" / "crashing" …
    var isRunning: Bool { (status ?? "") == "running" }

    var statusTone: StatusPill.Tone {
        switch status ?? "" {
        case "running":  return .ok
        case "starting", "restarting": return .warn
        case "failed", "crashed", "exited": return .bad
        default: return .idle
        }
    }

    var statusLabel: String {
        switch status ?? "" {
        case "running":  return "运行中"
        case "stopped":  return "已停止"
        case "starting": return "启动中"
        case "restarting": return "重启中"
        case "failed":   return "失败"
        case "crashed":  return "已崩溃"
        case "exited":   return "已退出"
        default:         return status ?? "未知"
        }
    }

    /// Uptime derived from started_at, e.g. "3 天 7 小时".
    var uptimeText: String? {
        guard isRunning, let s = startedAt, let d = ISO8601.date(from: s) else { return nil }
        let secs = Date().timeIntervalSince(d)
        guard secs > 0 else { return nil }
        let days = Int(secs) / 86400
        let hours = (Int(secs) % 86400) / 3600
        let mins = (Int(secs) % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(mins) 分" }
        return "\(mins) 分钟"
    }
}

struct BotList: Codable {
    let bots: [Bot]
    let workspace: String?
}

// MARK: - Host mode

/// GET /api/host/mode — the single call that drives the dashboard header.
struct HostMode: Codable {
    let host: Bool
    let authenticated: Bool
    let selectedBotID: String?
    let selectedBotRunning: Bool?

    enum CodingKeys: String, CodingKey {
        case host, authenticated
        case selectedBotID = "selected_bot_id"
        case selectedBotRunning = "selected_bot_running"
    }
}

// MARK: - Session

struct HostSession: Codable {
    let authenticated: Bool
}

struct AuthCheck: Codable {
    let authenticated: Bool
}

// MARK: - Settings (only the slice we display)

struct HostSettings: Codable {
    let revision: String?
    let webui: WebUI?

    struct WebUI: Codable {
        let hosts: [String]?
        let port: Int?
        let enabled: Bool?
        let antiCrawlerMode: String?
        let publicBaseURL: String?

        enum CodingKeys: String, CodingKey {
            case hosts, port, enabled
            case antiCrawlerMode = "anti_crawler_mode"
            case publicBaseURL = "public_base_url"
        }
    }
}

// MARK: - Log

struct LogChunk: Codable {
    let lines: [String]?
    let content: String?
    let path: String?
    let truncated: Bool?

    /// The API has changed shape across versions; accept either.
    var text: String {
        if let lines, !lines.isEmpty { return lines.joined(separator: "\n") }
        return content ?? ""
    }
}

// MARK: - Errors

struct APIErrorBody: Codable {
    let detail: String?
    let error: String?
    let message: String?
    var display: String {
        detail ?? error ?? message ?? "未知错误"
    }
}

// MARK: - Dates

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s)
    }
}
