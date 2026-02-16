import Foundation
import Combine

@MainActor
final class OpenCodeReader: ObservableObject {
    @Published var stats: OpenCodeStats?
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var error: String?

    // SSH target — configure via environment or defaults
    let host: String
    let user: String
    let scriptPath: String

    private var timer: Timer?

    init(host: String = "10.0.0.50", user: String = "douglaswhittingham", scriptPath: String = "opencode-stats.py") {
        self.host = host
        self.user = user
        self.scriptPath = scriptPath
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task.detached { [host, user, scriptPath] in
            let result = Self.runSSH(host: host, user: user, scriptPath: scriptPath)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let stats):
                    self.stats = stats
                    self.lastUpdated = Date()
                    self.error = nil
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }
    }

    private nonisolated static func runSSH(host: String, user: String, scriptPath: String) -> Result<OpenCodeStats, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes",
            "\(user)@\(host)",
            "python \(scriptPath)"
        ]

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "SSH failed (exit \(process.terminationStatus))"
                return .failure(NSError(domain: "OpenCodeReader", code: Int(process.terminationStatus),
                                       userInfo: [NSLocalizedDescriptionKey: errStr]))
            }

            let decoded = try JSONDecoder().decode(OpenCodeStats.self, from: data)
            return .success(decoded)
        } catch {
            return .failure(error)
        }
    }

    func startPolling(interval: TimeInterval = 120) {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.load()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Computed helpers (mirror StatsReader interface)

    var allTimeTokens: Int {
        guard let usage = stats?.modelUsage else { return 0 }
        return usage.values.reduce(0) { $0 + $1.input + $1.output }
    }

    var modelBreakdown: [(model: String, tokens: Int)] {
        guard let usage = stats?.modelUsage else { return [] }
        return usage
            .map { (model: $0.key, tokens: $0.value.input + $0.value.output) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    var dailyTokenMap: [String: Int] {
        guard let daily = stats?.dailyModelTokens else { return [:] }
        var map: [String: Int] = [:]
        for entry in daily {
            map[entry.date] = entry.tokensByModel.values.reduce(0, +)
        }
        return map
    }

    var dailyActivityMap: [String: DailyActivity] {
        guard let activity = stats?.dailyActivity else { return [:] }
        var map: [String: DailyActivity] = [:]
        for entry in activity {
            map[entry.date] = DailyActivity(
                date: entry.date,
                messageCount: entry.messageCount,
                sessionCount: entry.sessionCount,
                toolCallCount: nil
            )
        }
        return map
    }

    var todayDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    var todayTotalTokens: Int {
        dailyTokenMap[todayDateString] ?? 0
    }

    var todayTopModel: String? {
        guard let daily = stats?.dailyModelTokens.first(where: { $0.date == todayDateString }) else { return nil }
        return daily.tokensByModel.max(by: { $0.value < $1.value })?.key
    }

    var todayMessages: Int {
        stats?.dailyActivity.first(where: { $0.date == todayDateString })?.messageCount ?? 0
    }

    var todaySessions: Int {
        stats?.dailyActivity.first(where: { $0.date == todayDateString })?.sessionCount ?? 0
    }

    // MARK: - Cost estimation

    var estimatedTotalCost: Double {
        guard let usage = stats?.modelUsage else { return 0 }
        return usage.reduce(0.0) { total, entry in
            total + TokenFormatter.estimateCostOpenCode(model: entry.key, usage: entry.value)
        }
    }

    var costByModel: [(model: String, cost: Double)] {
        guard let usage = stats?.modelUsage else { return [] }
        return usage
            .map { (model: $0.key, cost: TokenFormatter.estimateCostOpenCode(model: $0.key, usage: $0.value)) }
            .filter { $0.cost > 0 }
            .sorted { $0.cost > $1.cost }
    }

    var detailedCostBreakdown: [StatsReader.ModelCostBreakdown] {
        guard let usage = stats?.modelUsage else { return [] }
        return usage.compactMap { modelId, u in
            guard let price = TokenFormatter.pricing[modelId] else { return nil }
            let lines = [
                StatsReader.CostBreakdownLine(label: "Input", tokens: u.input, rate: price.inputPerMillion,
                                              cost: Double(u.input) / 1_000_000 * price.inputPerMillion),
                StatsReader.CostBreakdownLine(label: "Output", tokens: u.output, rate: price.outputPerMillion,
                                              cost: Double(u.output) / 1_000_000 * price.outputPerMillion),
                StatsReader.CostBreakdownLine(label: "Cache Read", tokens: u.cacheRead, rate: price.cacheReadPerMillion,
                                              cost: Double(u.cacheRead) / 1_000_000 * price.cacheReadPerMillion),
            ]
            let total = lines.reduce(0) { $0 + $1.cost }
            guard total > 0 else { return nil }
            return StatsReader.ModelCostBreakdown(model: modelId, lines: lines, total: total)
        }
        .sorted { $0.total > $1.total }
    }

    var currentStreak: Int {
        guard let activity = stats?.dailyActivity, !activity.isEmpty else { return 0 }
        var dates = Set<String>()
        for entry in activity { dates.insert(entry.date) }
        if let tokens = stats?.dailyModelTokens {
            for entry in tokens { dates.insert(entry.date) }
        }
        guard !dates.isEmpty else { return 0 }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current

        var streak = 0
        var checkDate = Date()
        let todayStr = fmt.string(from: checkDate)

        if !dates.contains(todayStr) {
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate)!
            if !dates.contains(fmt.string(from: checkDate)) { return 0 }
        }

        while dates.contains(fmt.string(from: checkDate)) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }
}
