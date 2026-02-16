import Foundation

// MARK: - Provider

enum StatsProvider: String, CaseIterable {
    case claudeCode = "Claude Code"
    case openCode = "OpenCode"
    case all = "All"
}

// MARK: - Claude Code (stats-cache.json)

struct StatsCache: Codable {
    let version: Int
    let lastComputedDate: String
    let dailyActivity: [DailyActivity]
    let dailyModelTokens: [DailyModelTokens]
    let modelUsage: [String: ModelUsage]
    let totalSessions: Int
    let totalMessages: Int
    let hourCounts: [String: Int]?
}

struct DailyActivity: Codable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int?
}

struct DailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]
}

struct ModelUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
}

// MARK: - OpenCode (aggregated from message JSON files)

struct OpenCodeStats: Codable {
    let source: String
    let providers: [String]
    let totalSessions: Int
    let totalMessages: Int
    let modelUsage: [String: OpenCodeModelUsage]
    let dailyModelTokens: [DailyModelTokens]
    let dailyActivity: [OpenCodeDailyActivity]
}

struct OpenCodeModelUsage: Codable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cacheRead: Int
    let cacheWrite: Int
}

struct OpenCodeDailyActivity: Codable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
}
