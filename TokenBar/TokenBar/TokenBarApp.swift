import SwiftUI
import ServiceManagement

@main
struct TokenBarApp: App {
    @StateObject private var reader = StatsReader()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(reader: reader)
        } label: {
            Text(reader.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupGlobalHotkey()
    }

    private func setupGlobalHotkey() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                // Re-enable tap if disabled by system
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let tap = Unmanaged<AnyObject>.fromOpaque(refcon).takeUnretainedValue() as! AppDelegate
                        if let machPort = tap.eventTap {
                            CGEvent.tapEnable(tap: machPort, enable: true)
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                // Cmd+Shift+T: keyCode 17, check for cmd+shift without other modifiers
                let wantedFlags: CGEventFlags = [.maskCommand, .maskShift]
                let relevantFlags = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])

                if keyCode == 17 && relevantFlags == wantedFlags {
                    DispatchQueue.main.async {
                        AppDelegate.togglePanel()
                    }
                    return nil // swallow the event
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Grant Accessibility access in System Settings > Privacy & Security > Accessibility")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Global hotkey Cmd+Shift+T active")
    }

    static func togglePanel() {
        // Look for the MenuBarExtra panel window
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("Panel") || name.contains("MenuBarExtra") || name.contains("_NSPopoverWindow") {
                if window.isVisible {
                    window.orderOut(nil)
                } else {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                return
            }
        }
        // Fallback: just activate
        NSApp.activate(ignoringOtherApps: true)
    }
}
