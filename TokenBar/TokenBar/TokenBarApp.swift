import SwiftUI
import ServiceManagement

@main
struct TokenBarApp: App {
    @StateObject private var reader = StatsReader()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(reader: reader)
        } label: {
            Text(reader.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
