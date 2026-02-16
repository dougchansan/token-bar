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

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
                Text("Token Bar")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(brightText)
                Spacer()
                if let updated = reader.lastUpdated {
                    Text(updated, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(dimText)
                }
            }
            .padding(.bottom, 2)

            // Today card
            todayCard

            // Insights row: streak, peak hour, cost
            insightsRow

            // All Time card
            allTimeCard

            // Model breakdown with cost
            modelCard

            // Heatmap
            heatmapCard

            // Peak hours chart
            peakHoursCard

            // Actions
            actionsRow
        }
        .padding(14)
        .frame(width: 420)
        .background(bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Today", systemImage: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                if reader.liveTokens.messageCount > 0 {
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
                if let model = reader.todayTopModel {
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
                    value: TokenFormatter.format(reader.todayTotalTokens),
                    label: "Tokens",
                    color: accent
                )
                metricTile(
                    value: TokenFormatter.formatWithCommas(reader.todayMessages),
                    label: "Messages",
                    color: bodyText
                )
                metricTile(
                    value: "\(reader.todaySessions)",
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
                    value: "\(reader.currentStreak)",
                    label: "day streak"
                )

                // Peak hour
                if let peak = reader.peakHour {
                    insightPill(
                        icon: "clock.fill",
                        iconColor: warm,
                        value: TokenFormatter.formatHour(peak.hour),
                        label: "peak hour"
                    )
                }

                // Total cost (clickable)
                Button {
                    showCostBreakdown.toggle()
                } label: {
                    insightPill(
                        icon: "dollarsign.circle.fill",
                        iconColor: green,
                        value: TokenFormatter.formatCost(reader.estimatedTotalCost),
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
        let breakdowns = reader.detailedCostBreakdown

        return VStack(spacing: 8) {
            HStack {
                Label("Cost Breakdown", systemImage: "dollarsign.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(green)
                    .textCase(.uppercase)
                Spacer()
                Text("Estimated · Anthropic API pricing")
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
                Text(TokenFormatter.formatCost(reader.estimatedTotalCost))
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
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                Spacer()
            }

            HStack(spacing: 0) {
                metricTile(
                    value: TokenFormatter.format(reader.allTimeTokens),
                    label: "Tokens",
                    color: accent
                )
                if let stats = reader.stats {
                    metricTile(
                        value: TokenFormatter.formatWithCommas(stats.totalMessages),
                        label: "Messages",
                        color: bodyText
                    )
                    metricTile(
                        value: "\(stats.totalSessions)",
                        label: "Sessions",
                        color: bodyText
                    )
                }
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
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                Spacer()
            }

            let breakdown = reader.modelBreakdown
            let costBreakdown = Dictionary(uniqueKeysWithValues: reader.costByModel.map { ($0.model, $0.cost) })
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
                Text(TokenFormatter.formatCost(cost))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(green.opacity(0.8))
                    .padding(.trailing, 6)
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
                                colors: [accentDim, accent],
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
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                Spacer()
            }

            let numWeeks = 16
            let tokenMap = reader.dailyTokenMap
            let activityMap = reader.dailyActivityMap
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

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            actionButton("arrow.clockwise", "Refresh") {
                reader.load()
                reader.scanLiveSessions()
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

            Text("\u{2318}\u{21E7}T")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(dimText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))

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
                .foregroundStyle(accent)
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
                        isToday ? accent.opacity(0.8) :
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
