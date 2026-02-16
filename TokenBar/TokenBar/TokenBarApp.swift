import SwiftUI
import ServiceManagement

@main
struct TokenBarApp: App {
    @StateObject private var reader = StatsReader()
    @StateObject private var openCodeReader = OpenCodeReader()
    @State private var provider: StatsProvider = .claudeCode

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(reader: reader, openCodeReader: openCodeReader, provider: $provider)
        } label: {
            Text(menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: String {
        switch provider {
        case .claudeCode:
            return reader.menuBarLabel
        case .openCode:
            let model = openCodeReader.todayTopModel.map { TokenFormatter.friendlyModelName($0) } ?? "OpenCode"
            let tokens = TokenFormatter.format(openCodeReader.todayTotalTokens)
            return "\u{25C6} \(model) | \(tokens)"
        case .all:
            let totalTokens = reader.todayTotalTokens + openCodeReader.todayTotalTokens
            return "\u{25C6} All | \(TokenFormatter.format(totalTokens))"
        }
    }
}
