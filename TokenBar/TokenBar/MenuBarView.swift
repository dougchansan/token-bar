import SwiftUI
import ServiceManagement

struct HeatmapDayInfo: Equatable {
    let dateString: String
    let tokens: Int
    let messages: Int
    let sessions: Int
}

struct MenuBarView: View {
    @ObservedObject var reader: StatsReader
    @ObservedObject var openCodeReader: OpenCodeReader
    @Binding var provider: StatsProvider
    @State private var hoveredDay: HeatmapDayInfo?
    @State private var showCostBreakdown = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let bg = Color(white: 0.11)
    private let cardBg = Color(white: 0.15)
    private let dimText = Color(white: 0.45)
    private let bodyText = Color(white: 0.82)
    private let brightText = Color.white
    private let accent = Color(red: 0.4, green: 0.6, blue: 1.0)
    private let accentDim = Color(red: 0.25, green: 0.4, blue: 0.75)
    private let warm = Color(red: 1.0, green: 0.75, blue: 0.35)
    private let green = Color(red: 0.3, green: 0.85, blue: 0.5)
    private let openCodeAccent = Color(red: 0.9, green: 0.5, blue: 0.2)

    // MARK: - Unified data accessors

    private var activeAccent: Color {
        provider == .openCode ? openCodeAccent : accent
    }

    private var activeTodayTokens: Int {
        switch provider {
        case .claudeCode: return reader.todayTotalTokens
        case .openCode: return openCodeReader.todayTotalTokens
        case .all: return reader.todayTotalTokens + openCodeReader.todayTotalTokens
        }
    }

    private var activeTodayMessages: Int {
        switch provider {
        case .claudeCode: return reader.todayMessages
        case .openCode: return openCodeReader.todayMessages
        case .all: return reader.todayMessages + openCodeReader.todayMessages
        }
    }

    private var activeTodaySessions: Int {
        switch provider {
        case .claudeCode: return reader.todaySessions
        case .openCode: return openCodeReader.todaySessions
        case .all: return reader.todaySessions + openCodeReader.todaySessions
        }
    }

    private var activeTodayTopModel: String? {
        switch provider {
        case .claudeCode: return reader.todayTopModel
        case .openCode: return openCodeReader.todayTopModel
        case .all: return reader.todayTopModel ?? openCodeReader.todayTopModel
        }
    }

    private var activeAllTimeTokens: Int {
        switch provider {
        case .claudeCode: return reader.allTimeTokens
        case .openCode: return openCodeReader.allTimeTokens
        case .all: return reader.allTimeTokens + openCodeReader.allTimeTokens
        }
    }

    private var activeTotalMessages: Int {
        switch provider {
        case .claudeCode: return reader.stats?.totalMessages ?? 0
        case .openCode: return openCodeReader.stats?.totalMessages ?? 0
        case .all: return (reader.stats?.totalMessages ?? 0) + (openCodeReader.stats?.totalMessages ?? 0)
        }
    }

    private var activeTotalSessions: Int {
        switch provider {
        case .claudeCode: return reader.stats?.totalSessions ?? 0
        case .openCode: return openCodeReader.stats?.totalSessions ?? 0
        case .all: return (reader.stats?.totalSessions ?? 0) + (openCodeReader.stats?.totalSessions ?? 0)
        }
    }

    private var activeModelBreakdown: [(model: String, tokens: Int)] {
        switch provider {
        case .claudeCode: return reader.modelBreakdown
        case .openCode: return openCodeReader.modelBreakdown
        case .all:
            var map: [String: Int] = [:]
            for entry in reader.modelBreakdown { map[entry.model, default: 0] += entry.tokens }
            for entry in openCodeReader.modelBreakdown { map[entry.model, default: 0] += entry.tokens }
            return map.map { (model: $0.key, tokens: $0.value) }
                .filter { $0.tokens > 0 }
                .sorted { $0.tokens > $1.tokens }
        }
    }

    private var activeDailyTokenMap: [String: Int] {
        switch provider {
        case .claudeCode: return reader.dailyTokenMap
        case .openCode: return openCodeReader.dailyTokenMap
        case .all:
            var map = reader.dailyTokenMap
            for (date, tokens) in openCodeReader.dailyTokenMap {
                map[date, default: 0] += tokens
            }
            return map
        }
    }

    private var activeDailyActivityMap: [String: DailyActivity] {
        switch provider {
        case .claudeCode: return reader.dailyActivityMap
        case .openCode: return openCodeReader.dailyActivityMap
        case .all:
            var map = reader.dailyActivityMap
            for (date, activity) in openCodeReader.dailyActivityMap {
                if let existing = map[date] {
                    map[date] = DailyActivity(
                        date: date,
                        messageCount: existing.messageCount + activity.messageCount,
                        sessionCount: existing.sessionCount + activity.sessionCount,
                        toolCallCount: existing.toolCallCount
                    )
                } else {
                    map[date] = activity
                }
            }
            return map
        }
    }

    private var activeEstimatedCost: Double {
        switch provider {
        case .claudeCode: return reader.estimatedTotalCost
        case .openCode: return openCodeReader.estimatedTotalCost
        case .all: return reader.estimatedTotalCost + openCodeReader.estimatedTotalCost
        }
    }

    private var activeCostByModel: [(model: String, cost: Double)] {
        switch provider {
        case .claudeCode: return reader.costByModel
        case .openCode: return openCodeReader.costByModel
        case .all:
            var map: [String: Double] = [:]
            for entry in reader.costByModel { map[entry.model, default: 0] += entry.cost }
            for entry in openCodeReader.costByModel { map[entry.model, default: 0] += entry.cost }
            return map.map { (model: $0.key, cost: $0.value) }
                .filter { $0.cost > 0 }
                .sorted { $0.cost > $1.cost }
        }
    }

    private var activeCostBreakdown: [StatsReader.ModelCostBreakdown] {
        switch provider {
        case .claudeCode: return reader.detailedCostBreakdown
        case .openCode: return openCodeReader.detailedCostBreakdown
        case .all: return reader.detailedCostBreakdown + openCodeReader.detailedCostBreakdown
        }
    }

    private var activeStreak: Int {
        switch provider {
        case .claudeCode: return reader.currentStreak
        case .openCode: return openCodeReader.currentStreak
        case .all:
            // Merge all dates for combined streak
            var dates = Set<String>()
            if let activity = reader.stats?.dailyActivity {
                for entry in activity { dates.insert(entry.date) }
            }
            if let tokens = reader.stats?.dailyModelTokens {
                for entry in tokens { dates.insert(entry.date) }
            }
            if reader.liveTokens.messageCount > 0 {
                dates.insert(reader.todayDateString)
            }
            if let activity = openCodeReader.stats?.dailyActivity {
                for entry in activity { dates.insert(entry.date) }
            }
            if let tokens = openCodeReader.stats?.dailyModelTokens {
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

    var body: some View {
        VStack(spacing: 10) {
            // Header with provider toggle
            headerRow

            // Today card
            todayCard

            // Insights row: streak, peak hour, cost
            insightsRow

            // All Time card
            allTimeCard

            // Model breakdown
            modelCard

            // Heatmap
            heatmapCard

            // Peak hours chart (Claude Code only — OpenCode doesn't have hourCounts)
            if provider != .openCode {
                peakHoursCard
            }

            // Connection status for OpenCode
            if provider != .claudeCode {
                openCodeStatusRow
            }

            // Actions
            actionsRow
        }
        .padding(14)
        .frame(width: 420)
        .background(bg)
        .preferredColorScheme(.dark)
        .onAppear {
            if provider != .claudeCode && openCodeReader.stats == nil {
                openCodeReader.load()
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 10))
                .foregroundStyle(activeAccent)
            Text("Token Bar")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(brightText)
            Spacer()

            // Provider picker
            providerPicker

            if let updated = provider == .openCode ? openCodeReader.lastUpdated : reader.lastUpdated {
                Text(updated, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(dimText)
            }
        }
        .padding(.bottom, 2)
    }

    private var providerPicker: some View {
        HStack(spacing: 0) {
            ForEach(StatsProvider.allCases, id: \.rawValue) { p in
                Button {
                    provider = p
                    if p != .claudeCode && openCodeReader.stats == nil {
                        openCodeReader.load()
                    }
                } label: {
                    Text(p == .claudeCode ? "Claude" : p == .openCode ? "Open" : "All")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(provider == p ? brightText : dimText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            provider == p
                                ? (p == .openCode ? openCodeAccent.opacity(0.3) : accent.opacity(0.3))
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Today", systemImage: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activeAccent)
                    .textCase(.uppercase)
                if provider != .openCode && reader.liveTokens.messageCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(green)
                            .frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(green)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(green.opacity(0.1), in: Capsule())
                }
                Spacer()
                if let model = activeTodayTopModel {
                    Text(TokenFormatter.friendlyModelName(model))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(warm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(warm.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 0) {
                metricTile(
                    value: TokenFormatter.format(activeTodayTokens),
                    label: "Tokens",
                    color: activeAccent
                )
                metricTile(
                    value: TokenFormatter.formatWithCommas(activeTodayMessages),
                    label: "Messages",
                    color: bodyText
                )
                metricTile(
                    value: "\(activeTodaySessions)",
                    label: "Sessions",
                    color: bodyText
                )
            }
        }
        .cardStyle(cardBg)
    }

    // MARK: - Insights row

    private var insightsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Streak
                insightPill(
                    icon: "flame.fill",
                    iconColor: Color(red: 1.0, green: 0.45, blue: 0.2),
                    value: "\(activeStreak)",
                    label: "day streak"
                )

                // Peak hour (Claude Code only)
                if provider != .openCode, let peak = reader.peakHour {
                    insightPill(
                        icon: "clock.fill",
                        iconColor: warm,
                        value: TokenFormatter.formatHour(peak.hour),
                        label: "peak hour"
                    )
                }

                // Total cost
                Button {
                    showCostBreakdown.toggle()
                } label: {
                    insightPill(
                        icon: "dollarsign.circle.fill",
                        iconColor: green,
                        value: TokenFormatter.formatCost(activeEstimatedCost),
                        label: showCostBreakdown ? "tap to hide" : "tap for detail"
                    )
                }
                .buttonStyle(.plain)
            }

            // Cost breakdown (shown on click)
            if showCostBreakdown {
                costBreakdownCard
            }
        }
    }

    // MARK: - Cost Breakdown

    private var costBreakdownCard: some View {
        let breakdowns = activeCostBreakdown

        return VStack(spacing: 8) {
            HStack {
                Label("Cost Breakdown", systemImage: "dollarsign.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(green)
                    .textCase(.uppercase)
                Spacer()
                Text(provider == .claudeCode ? "Estimated · Anthropic API pricing" :
                     provider == .openCode ? "Estimated · Moonshot API pricing" :
                     "Estimated · API pricing")
                    .font(.system(size: 8))
                    .foregroundStyle(dimText)
            }

            ForEach(Array(breakdowns.enumerated()), id: \.offset) { _, breakdown in
                VStack(spacing: 4) {
                    HStack {
                        Text(TokenFormatter.friendlyModelName(breakdown.model))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(bodyText)
                        Spacer()
                        Text(TokenFormatter.formatCost(breakdown.total))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(green)
                    }

                    let visibleLines = breakdown.lines.filter { $0.cost > 0.001 }
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 4) {
                            Text(line.label)
                                .font(.system(size: 9))
                                .foregroundStyle(dimText)
                                .frame(width: 70, alignment: .leading)
                            Text(TokenFormatter.format(line.tokens))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(dimText)
                            Text("@")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(white: 0.3))
                            Text("$\(String(format: "%.2f", line.rate))/M")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(dimText)
                            Spacer()
                            Text(TokenFormatter.formatCost(line.cost))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(bodyText)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Text("Total:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(bodyText)
                Text(TokenFormatter.formatCost(activeEstimatedCost))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(green)
            }
        }
        .cardStyle(cardBg)
    }

    private func insightPill(icon: String, iconColor: Color, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(brightText)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(dimText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - All Time

    private var allTimeCard: some View {
        VStack(spacing: 8) {
            HStack {
                Label("All Time", systemImage: "infinity")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activeAccent)
                    .textCase(.uppercase)
                Spacer()
            }

            HStack(spacing: 0) {
                metricTile(
                    value: TokenFormatter.format(activeAllTimeTokens),
                    label: "Tokens",
                    color: activeAccent
                )
                metricTile(
                    value: TokenFormatter.formatWithCommas(activeTotalMessages),
                    label: "Messages",
                    color: bodyText
                )
                metricTile(
                    value: "\(activeTotalSessions)",
                    label: "Sessions",
                    color: bodyText
                )
            }
        }
        .cardStyle(cardBg)
    }

    // MARK: - Models

    private var modelCard: some View {
        VStack(spacing: 6) {
            HStack {
                Label("By Model", systemImage: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activeAccent)
                    .textCase(.uppercase)
                Spacer()
            }

            let breakdown = activeModelBreakdown
            let costBreakdown = Dictionary(uniqueKeysWithValues: activeCostByModel.map { ($0.model, $0.cost) })
            let maxTokens = breakdown.first?.tokens ?? 1

            ForEach(breakdown, id: \.model) { entry in
                modelRow(
                    name: TokenFormatter.friendlyModelName(entry.model),
                    tokens: entry.tokens,
                    cost: costBreakdown[entry.model] ?? 0,
                    fraction: Double(entry.tokens) / Double(maxTokens)
                )
            }
        }
        .cardStyle(cardBg)
    }

    private func modelRow(name: String, tokens: Int, cost: Double, fraction: Double) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(bodyText)
                Spacer()
                if cost > 0 {
                    Text(TokenFormatter.formatCost(cost))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(green.opacity(0.8))
                        .padding(.trailing, 6)
                }
                Text(TokenFormatter.format(tokens))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(brightText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [activeAccent.opacity(0.6), activeAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fraction, height: 3)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Activity", systemImage: "square.grid.3x3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activeAccent)
                    .textCase(.uppercase)
                Spacer()
            }

            let numWeeks = 16
            let tokenMap = activeDailyTokenMap
            let activityMap = activeDailyActivityMap
            let weeks = reader.heatmapWeeks(weeks: numWeeks)
            let allValues = tokenMap.values.filter { $0 > 0 }
            let maxVal = allValues.max() ?? 1
            let cellSpacing: CGFloat = 3
            let dayLabelWidth: CGFloat = 16

            let dayLabels = ["", "M", "", "W", "", "F", ""]
            let monthLabels = heatmapMonthLabels(weeks: weeks)

            GeometryReader { geo in
                let availableWidth = geo.size.width - dayLabelWidth - cellSpacing
                let cellSize = (availableWidth - cellSpacing * CGFloat(numWeeks - 1)) / CGFloat(numWeeks)

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: cellSpacing) {
                        Color.clear.frame(width: dayLabelWidth, height: 14)
                        ForEach(Array(monthLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(dimText)
                                .frame(width: cellSize, height: 14)
                        }
                    }

                    HStack(alignment: .top, spacing: cellSpacing) {
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { i in
                                Text(dayLabels[i])
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(dimText)
                                    .frame(width: dayLabelWidth, height: cellSize)
                            }
                        }

                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: cellSpacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    let tokens = tokenMap[day.dateString] ?? 0
                                    let activity = activityMap[day.dateString]
                                    let isFuture = day.date > Date()
                                    let isToday = day.dateString == reader.todayDateString
                                    let isHovered = hoveredDay?.dateString == day.dateString
                                    let dayInfo = HeatmapDayInfo(
                                        dateString: day.dateString,
                                        tokens: tokens,
                                        messages: activity?.messageCount ?? 0,
                                        sessions: activity?.sessionCount ?? 0
                                    )

                                    heatmapCell(
                                        tokens: tokens, maxVal: maxVal,
                                        isFuture: isFuture, isToday: isToday,
                                        isHovered: isHovered,
                                        size: cellSize
                                    )
                                    .onHover { hovering in
                                        if hovering && !isFuture {
                                            hoveredDay = dayInfo
                                        } else if hoveredDay?.dateString == day.dateString {
                                            hoveredDay = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: {
                let approxCell: CGFloat = 20
                return 14 + 7 * approxCell + 6 * 3
            }())

            if let day = hoveredDay {
                heatmapTooltip(day)
                    .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    Spacer()
                    Text("Less")
                        .font(.system(size: 8))
                        .foregroundStyle(dimText)
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatColor(level))
                            .frame(width: 10, height: 10)
                    }
                    Text("More")
                        .font(.system(size: 8))
                        .foregroundStyle(dimText)
                }
                .padding(.top, 2)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredDay)
        .cardStyle(cardBg)
    }

    // MARK: - Peak Hours

    private var peakHoursCard: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Peak Hours", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                Spacer()
                if let peak = reader.peakHour {
                    Text("\(peak.sessions) sessions at \(TokenFormatter.formatHour(peak.hour))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(dimText)
                }
            }

            let hours = reader.hourDistribution
            let maxCount = hours.map(\.count).max() ?? 1

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours, id: \.hour) { entry in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                entry.count == maxCount && entry.count > 0
                                    ? warm
                                    : accent.opacity(entry.count > 0 ? 0.3 + 0.7 * Double(entry.count) / Double(maxCount) : 0.08)
                            )
                            .frame(height: max(2, CGFloat(entry.count) / CGFloat(maxCount) * 32))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 32)

            // Hour labels
            HStack(spacing: 0) {
                Text("12a")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("6a")
                    .frame(maxWidth: .infinity)
                Text("12p")
                    .frame(maxWidth: .infinity)
                Text("6p")
                    .frame(maxWidth: .infinity)
                Text("12a")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(dimText)
        }
        .cardStyle(cardBg)
    }

    // MARK: - OpenCode Status

    private var openCodeStatusRow: some View {
        HStack(spacing: 6) {
            if openCodeReader.isLoading {
                ProgressView()
                    .controlSize(.mini)
                Text("Connecting to \(openCodeReader.host)...")
                    .font(.system(size: 10))
                    .foregroundStyle(dimText)
            } else if let error = openCodeReader.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(dimText)
                    .lineLimit(1)
            } else if openCodeReader.stats != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(green)
                Text("Connected to \(openCodeReader.host)")
                    .font(.system(size: 10))
                    .foregroundStyle(dimText)
            }
            Spacer()
            Button {
                openCodeReader.load()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(dimText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            actionButton("arrow.clockwise", "Refresh") {
                reader.load()
                reader.scanLiveSessions()
                if provider != .claudeCode {
                    openCodeReader.load()
                }
            }

            Toggle(isOn: $launchAtLogin) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                    Text("Login")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(dimText)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Launch at login error: \(error)")
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            Spacer()

            actionButton("power", "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Heatmap helpers

    private func heatmapTooltip(_ day: HeatmapDayInfo) -> some View {
        HStack(spacing: 12) {
            Text(formatHeatmapDateLong(day.dateString))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(brightText)
            Spacer()
            HStack(spacing: 10) {
                tooltipMetric(value: TokenFormatter.format(day.tokens), label: "tokens")
                tooltipMetric(value: TokenFormatter.formatWithCommas(day.messages), label: "msgs")
                tooltipMetric(value: "\(day.sessions)", label: "sess")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
    }

    private func tooltipMetric(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(activeAccent)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(dimText)
                .textCase(.uppercase)
        }
    }

    private func heatmapMonthLabels(weeks: [[(date: Date, dateString: String)]]) -> [String] {
        let cal = Calendar.current
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMM"

        var labels: [String] = []
        var lastMonth = -1

        for week in weeks {
            guard let sunday = week.first else { labels.append(""); continue }
            let month = cal.component(.month, from: sunday.date)
            if month != lastMonth {
                labels.append(monthFmt.string(from: sunday.date))
                lastMonth = month
            } else {
                labels.append("")
            }
        }
        return labels
    }

    private func formatHeatmapDateLong(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "January", "February", "March", "April", "May", "June",
                       "July", "August", "September", "October", "November", "December"]
        let month = Int(parts[1]) ?? 0
        let day = Int(parts[2]) ?? 0
        guard month > 0, month <= 12 else { return dateStr }
        return "\(months[month]) \(day), \(parts[0])"
    }

    private func heatmapCell(tokens: Int, maxVal: Int, isFuture: Bool, isToday: Bool = false, isHovered: Bool = false, size: CGFloat = 12) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isFuture ? Color.clear : heatColor(tokens > 0 ? Double(tokens) / Double(maxVal) : 0))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        isHovered ? brightText.opacity(0.9) :
                        isToday ? activeAccent.opacity(0.8) :
                        (isFuture ? Color.clear : Color.white.opacity(0.04)),
                        lineWidth: isHovered ? 1.5 : (isToday ? 1.5 : 0.5)
                    )
            )
            .scaleEffect(isHovered ? 1.3 : 1.0)
            .zIndex(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private func heatColor(_ intensity: Double) -> Color {
        if intensity <= 0 { return Color.white.opacity(0.04) }
        let level: Double
        if intensity < 0.15 { level = 0.25 }
        else if intensity < 0.4 { level = 0.5 }
        else if intensity < 0.7 { level = 0.75 }
        else { level = 1.0 }

        if provider == .openCode {
            // Orange heatmap for OpenCode
            return Color(
                red: 0.6 + 0.4 * level,
                green: 0.3 + 0.2 * level,
                blue: 0.1 + 0.1 * level
            ).opacity(0.3 + 0.7 * level)
        }

        return Color(
            red: 0.2 + 0.2 * level,
            green: 0.35 + 0.3 * level,
            blue: 0.6 + 0.4 * level
        ).opacity(0.3 + 0.7 * level)
    }

    // MARK: - Helpers

    private func metricTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(dimText)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(dimText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card modifier

extension View {
    func cardStyle(_ bg: Color) -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 8))
    }
}
