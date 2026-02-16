import Foundation
import Combine

@MainActor
final class StatsReader: ObservableObject {
    @Published var stats: StatsCache?
    @Published var lastUpdated: Date?
    @Published var liveTokens: LiveTokens = LiveTokens()

    private let filePath: String
    private let claudeDir: String
    private var timer: Timer?
    private var lastModDate: Date?

    struct LiveTokens {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var messageCount: Int = 0
        var sessionCount: Int = 0
        var topModel: String?
        var modelTokens: [String: Int] = [:]
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.claudeDir = "\(home)/.claude"
        self.filePath = "\(claudeDir)/stats-cache.json"
        load()
        scanLiveSessions()
        startPolling()
    }

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath) else { return }

        do {
            let attrs = try fm.attributesOfItem(atPath: filePath)
            let modDate = attrs[.modificationDate] as? Date
            if let modDate, modDate == lastModDate { return }
            lastModDate = modDate

            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoded = try JSONDecoder().decode(StatsCache.self, from: data)
            stats = decoded
            lastUpdated = Date()
        } catch {
            print("StatsReader error: \(error)")
        }
    }

    // MARK: - Live session scanning

    func scanLiveSessions() {
        let fm = FileManager.default
        let projectsDir = "\(claudeDir)/projects"
        guard fm.fileExists(atPath: projectsDir) else { return }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())

        var live = LiveTokens()
        var sessionFiles: Set<String> = []

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return }

        for project in projectDirs {
            let projectPath = "\(projectsDir)/\(project)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let fullPath = "\(projectPath)/\(file)"
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate >= startOfToday else { continue }

                let sessionId = String(file.dropLast(6))
                if sessionFiles.contains(sessionId) { continue }
                sessionFiles.insert(sessionId)

                parseSessionTokens(path: fullPath, since: startOfToday, into: &live)
            }
        }

        live.sessionCount = sessionFiles.count
        live.topModel = live.modelTokens.max(by: { $0.value < $1.value })?.key
        liveTokens = live
        lastUpdated = Date()
    }

    private func parseSessionTokens(path: String, since: Date, into live: inout LiveTokens) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return }

        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let usage: [String: Any]?
            if let message = json["message"] as? [String: Any],
               let u = message["usage"] as? [String: Any] {
                usage = u
            } else if let dataObj = json["data"] as? [String: Any],
                      let msg = dataObj["message"] as? [String: Any],
                      let innerMsg = msg["message"] as? [String: Any],
                      let u = innerMsg["usage"] as? [String: Any] {
                usage = u
            } else {
                usage = nil
            }

            guard let usage else { continue }

            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0

            live.inputTokens += input
            live.outputTokens += output
            live.messageCount += 1

            let model: String?
            if let message = json["message"] as? [String: Any] {
                model = message["model"] as? String
            } else if let dataObj = json["data"] as? [String: Any],
                      let msg = dataObj["message"] as? [String: Any],
                      let innerMsg = msg["message"] as? [String: Any] {
                model = innerMsg["model"] as? String
            } else {
                model = nil
            }

            if let model {
                live.modelTokens[model, default: 0] += output
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.load()
                self?.scanLiveSessions()
            }
        }
    }

    // MARK: - Computed helpers

    var todayDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    var todayActivity: DailyActivity? {
        stats?.dailyActivity.first { $0.date == todayDateString }
    }

    var todayModelTokens: DailyModelTokens? {
        stats?.dailyModelTokens.first { $0.date == todayDateString }
    }

    var todayTotalTokens: Int {
        let liveTotal = liveTokens.inputTokens + liveTokens.outputTokens
        let cached = todayModelTokens?.tokensByModel.values.reduce(0, +) ?? 0
        return max(liveTotal, cached)
    }

    var todayTopModel: String? {
        liveTokens.topModel ?? todayModelTokens?.tokensByModel.max(by: { $0.value < $1.value })?.key
    }

    var allTimeTokens: Int {
        guard let usage = stats?.modelUsage else { return 0 }
        return usage.values.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }

    var modelBreakdown: [(model: String, tokens: Int)] {
        guard let usage = stats?.modelUsage else { return [] }
        return usage
            .map { (model: $0.key, tokens: $0.value.inputTokens + $0.value.outputTokens) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    var dailyTokenMap: [String: Int] {
        guard let dailyTokens = stats?.dailyModelTokens else { return [:] }
        var map: [String: Int] = [:]
        for entry in dailyTokens {
            map[entry.date] = entry.tokensByModel.values.reduce(0, +)
        }
        let liveTotal = liveTokens.inputTokens + liveTokens.outputTokens
        if liveTotal > 0 {
            let today = todayDateString
            map[today] = max(map[today] ?? 0, liveTotal)
        }
        return map
    }

    func heatmapWeeks(weeks: Int = 8) -> [[(date: Date, dateString: String)]] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        let today = Date()
        let todayWeekday = cal.component(.weekday, from: today)
        let daysFromSunday = todayWeekday - 1
        let totalDays = weeks * 7
        let startOfGrid = cal.date(byAdding: .day, value: -(totalDays - 1) + (6 - daysFromSunday), to: today)!

        var result: [[(date: Date, dateString: String)]] = []
        var current = startOfGrid
        var week: [(date: Date, dateString: String)] = []

        for _ in 0..<totalDays {
            week.append((date: current, dateString: fmt.string(from: current)))
            if week.count == 7 {
                result.append(week)
                week = []
            }
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        if !week.isEmpty { result.append(week) }
        return result
    }

    var todaySessions: Int {
        max(liveTokens.sessionCount, todayActivity?.sessionCount ?? 0)
    }

    var todayMessages: Int {
        max(liveTokens.messageCount, todayActivity?.messageCount ?? 0)
    }

    var dailyActivityMap: [String: DailyActivity] {
        guard let activity = stats?.dailyActivity else { return [:] }
        var map: [String: DailyActivity] = [:]
        for entry in activity { map[entry.date] = entry }
        return map
    }

    // MARK: - Cost estimation

    var estimatedTotalCost: Double {
        guard let usage = stats?.modelUsage else { return 0 }
        return usage.reduce(0.0) { total, entry in
            total + TokenFormatter.estimateCost(model: entry.key, usage: entry.value)
        }
    }

    var costByModel: [(model: String, cost: Double)] {
        guard let usage = stats?.modelUsage else { return [] }
        return usage
            .map { (model: $0.key, cost: TokenFormatter.estimateCost(model: $0.key, usage: $0.value)) }
            .filter { $0.cost > 0 }
            .sorted { $0.cost > $1.cost }
    }

    struct CostBreakdownLine {
        let label: String
        let tokens: Int
        let rate: Double  // per million
        let cost: Double
    }

    struct ModelCostBreakdown {
        let model: String
        let lines: [CostBreakdownLine]
        let total: Double
    }

    var detailedCostBreakdown: [ModelCostBreakdown] {
        guard let usage = stats?.modelUsage else { return [] }
        return usage.compactMap { modelId, u in
            guard let price = TokenFormatter.pricing[modelId] else { return nil }
            let lines = [
                CostBreakdownLine(label: "Input", tokens: u.inputTokens, rate: price.inputPerMillion,
                                  cost: Double(u.inputTokens) / 1_000_000 * price.inputPerMillion),
                CostBreakdownLine(label: "Output", tokens: u.outputTokens, rate: price.outputPerMillion,
                                  cost: Double(u.outputTokens) / 1_000_000 * price.outputPerMillion),
                CostBreakdownLine(label: "Cache Read", tokens: u.cacheReadInputTokens, rate: price.cacheReadPerMillion,
                                  cost: Double(u.cacheReadInputTokens) / 1_000_000 * price.cacheReadPerMillion),
                CostBreakdownLine(label: "Cache Write", tokens: u.cacheCreationInputTokens, rate: price.cacheWritePerMillion,
                                  cost: Double(u.cacheCreationInputTokens) / 1_000_000 * price.cacheWritePerMillion),
            ]
            let total = lines.reduce(0) { $0 + $1.cost }
            guard total > 0 else { return nil }
            return ModelCostBreakdown(model: modelId, lines: lines, total: total)
        }
        .sorted { $0.total > $1.total }
    }

    // MARK: - Streak

    var currentStreak: Int {
        // Merge all known active dates from every source
        var dates = Set<String>()
        if let activity = stats?.dailyActivity {
            for entry in activity { dates.insert(entry.date) }
        }
        if let tokens = stats?.dailyModelTokens {
            for entry in tokens { dates.insert(entry.date) }
        }
        // Count today as active if we have live session data
        if liveTokens.messageCount > 0 {
            dates.insert(todayDateString)
        }

        guard !dates.isEmpty else { return 0 }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current

        var streak = 0
        var checkDate = Date()
        let todayStr = fmt.string(from: checkDate)

        // If no activity today, start from yesterday
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

    // MARK: - Peak hour

    var peakHour: (hour: Int, sessions: Int)? {
        guard let hourCounts = stats?.hourCounts, !hourCounts.isEmpty else { return nil }
        let max = hourCounts.max(by: { $0.value < $1.value })!
        return (hour: Int(max.key) ?? 0, sessions: max.value)
    }

    // MARK: - Hour distribution for chart

    var hourDistribution: [(hour: Int, count: Int)] {
        guard let hourCounts = stats?.hourCounts else { return [] }
        return (0..<24).map { hour in
            (hour: hour, count: hourCounts[String(hour)] ?? 0)
        }
    }

    var menuBarLabel: String {
        let model = todayTopModel.map { TokenFormatter.friendlyModelName($0) } ?? "Claude"
        let tokens = TokenFormatter.format(todayTotalTokens)
        return "\u{25C6} \(model) | \(tokens)"
    }
}
