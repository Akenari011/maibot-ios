//
//  Models.swift
//  MaiBot
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

    var isRunning: Bool { (status ?? "") == "running" }

    var statusLabel: String {
        switch status ?? "" {
        case "running":    return "运行中"
        case "stopped":    return "已停止"
        case "starting":   return "启动中"
        case "restarting": return "重启中"
        case "migrating":  return "迁移中"
        case "crash_loop": return "崩溃循环"
        case "failed":     return "失败"
        case "crashed":    return "已崩溃"
        case "exited":     return "已退出"
        default:           return status ?? "未知"
        }
    }

    var uptimeText: String? {
        guard isRunning, let s = startedAt, let d = ISO8601.date(from: s) else { return nil }
        let secs = Date().timeIntervalSince(d)
        guard secs > 0 else { return nil }
        let days = Int(secs) / 86400
        let hours = (Int(secs) % 86400) / 3600
        let mins = (Int(secs) % 3600) / 60
        if days > 0 { return "\(days)天\(hours)小时" }
        if hours > 0 { return "\(hours)小时\(mins)分" }
        return "\(mins)分钟"
    }
}

struct BotList: Codable {
    let bots: [Bot]
    let workspace: String?
}

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

struct AuthCheck: Codable { let authenticated: Bool }

// MARK: - Dashboard statistics

struct Dashboard: Codable {
    let summary: Summary
    let modelStats: [ModelStat]
    let hourlyData: [HourPoint]
    let recentActivity: [ActivityItem]?

    enum CodingKeys: String, CodingKey {
        case summary
        case modelStats = "model_stats"
        case hourlyData = "hourly_data"
        case recentActivity = "recent_activity"
    }

    struct ActivityItem: Codable, Identifiable {
        let timestamp: String
        let model: String?
        let requestType: String?
        let tokens: Double?
        let cost: Double?
        let timeCost: Double?
        var id: String { timestamp + "|" + (model ?? "") + "|" + (requestType ?? "") }

        enum CodingKeys: String, CodingKey {
            case timestamp, model, tokens, cost
            case requestType = "request_type"
            case timeCost = "time_cost"
        }

        var clock: String {
            guard timestamp.count >= 19 else { return timestamp }
            let i = timestamp.index(timestamp.startIndex, offsetBy: 11)
            let j = timestamp.index(i, offsetBy: 5)
            return String(timestamp[i..<j])
        }
    }

    struct Summary: Codable {
        let totalRequests: Double
        let totalCost: Double
        let totalTokens: Double
        let inputTokens: Double
        let outputTokens: Double
        let cacheHitRate: Double?
        let chatCacheHitRate: Double?
        let onlineTime: Double
        let totalMessages: Double
        let totalReplies: Double
        let avgResponseTime: Double

        enum CodingKeys: String, CodingKey {
            case totalRequests = "total_requests"
            case totalCost = "total_cost"
            case totalTokens = "total_tokens"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheHitRate = "cache_hit_rate"
            case chatCacheHitRate = "chat_cache_hit_rate"
            case onlineTime = "online_time"
            case totalMessages = "total_messages"
            case totalReplies = "total_replies"
            case avgResponseTime = "avg_response_time"
        }
    }

    struct ModelStat: Codable, Identifiable {
        let modelName: String
        let requestCount: Double
        let totalCost: Double
        let totalTokens: Double
        var id: String { modelName }

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case requestCount = "request_count"
            case totalCost = "total_cost"
            case totalTokens = "total_tokens"
        }
    }

    struct HourPoint: Codable, Identifiable {
        let timestamp: String
        let requests: Double
        let tokens: Double
        let inputTokens: Double
        let outputTokens: Double
        var id: String { timestamp }

        enum CodingKeys: String, CodingKey {
            case timestamp, requests, tokens
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        /// "18:00" for the chart axis.
        var hourLabel: String {
            let t = timestamp
            guard t.count >= 13 else { return t }
            let idx = t.index(t.startIndex, offsetBy: 11)
            let end = t.index(idx, offsetBy: 5)
            return String(t[idx..<end])
        }
    }
}

// MARK: - Local cache (storage card)

struct LocalCache: Codable {
    let directories: [Dir]
    let database: DB

    struct Dir: Codable, Identifiable {
        let key: String
        let label: String
        let fileCount: Double
        let totalSize: Double
        var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key, label
            case fileCount = "file_count"
            case totalSize = "total_size"
        }
    }

    struct DB: Codable {
        let totalSize: Double
        enum CodingKeys: String, CodingKey { case totalSize = "total_size" }
    }
}

// MARK: - News

struct NewsResponse: Codable {
    let items: [NewsItem]

    struct NewsItem: Codable, Identifiable {
        let id: String
        let title: String
        let summary: String?
        let source: String?
        let publishedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, title, summary, source
            case publishedAt = "published_at"
        }
    }
}

// MARK: - Errors & dates

struct APIErrorBody: Codable {
    let detail: String?
    let error: String?
    let message: String?
    var display: String { detail ?? error ?? message ?? "未知错误" }
}

enum ISO8601 {
    private static let a: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let b: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static func date(from s: String) -> Date? { a.date(from: s) ?? b.date(from: s) }
}
// MARK: - Chat streams (chat tab list)

struct ChatStream: Codable, Identifiable {
    let id: Int
    let sessionID: String
    let displayName: String
    let chatType: String?
    let platform: String?
    let latestMessage: String?
    let lastActiveAt: Double?
    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case displayName = "display_name"
        case chatType = "chat_type"
        case platform
        case latestMessage = "latest_message"
        case lastActiveAt = "last_active_at"
    }
    var subtitle: String {
        if let m = latestMessage, !m.isEmpty { return m }
        return (chatType ?? "") == "group" ? "群聊" : "私聊"
    }
    var timeText: String {
        guard let t = lastActiveAt, t > 0 else { return "" }
        let date = Date(timeIntervalSince1970: t)
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) { f.dateFormat = "HH:mm" }
        else if Calendar.current.isDateInYesterday(date) { return "昨天" }
        else { f.dateFormat = "M/d" }
        return f.string(from: date)
    }
}

struct ChatStreamList: Codable {
    let sessions: [ChatStream]
    let total: Int?
}

// MARK: - Model config

struct ModelConfigResponse: Codable {
    let config: ModelConfig
}

struct ModelConfig: Codable {
    let models: [ModelInfo]?

    struct ModelInfo: Codable, Identifiable {
        let modelIdentifier: String
        let name: String?
        let apiProvider: String?
        let modelType: String?
        let visual: Bool?

        var id: String { modelIdentifier + "|" + (apiProvider ?? "") }
        var displayName: String { name ?? modelIdentifier }

        enum CodingKeys: String, CodingKey {
            case modelIdentifier = "model_identifier"
            case name
            case apiProvider = "api_provider"
            case modelType = "model_type"
            case visual
        }
    }
}
