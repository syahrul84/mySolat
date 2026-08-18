import AppKit
import SwiftUI
import UserNotifications

@main
struct mySolatApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
                .environmentObject(state.clock)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
                .environmentObject(state.menuBarClock)
        }
        .menuBarExtraStyle(.window)

        // A regular window rather than the `Settings` scene: this app is an
        // LSUIElement agent, and a plain window is reliable to raise from the
        // popover without an app menu to host ⌘,.
        // No `.environmentObject(state.clock)` here on purpose: the settings
        // window must not re-render on the 1 Hz tick.
        Window("mySolat Settings", id: SettingsWindow.id) {
            SettingsView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}

/// The menu bar label. Kept tiny so the 1 Hz tick redraws as little as possible.
private struct MenuBarLabel: View {
    @EnvironmentObject private var state: AppState
    /// The coarse clock. Stopped entirely unless the style shows a countdown, in
    /// which case observing it is what redraws the label.
    @EnvironmentObject private var clock: Ticker

    var body: some View {
        let title = state.menuBarTitle(now: clock.now)
        HStack(spacing: 4) {
            Image(systemName: state.menuBarSymbol)
            if !title.isEmpty {
                Text(title)
            }
        }
        // Re-evaluate whenever the rendered text changes.
        .id(title + state.menuBarSymbol)
        // The menu bar label is the one view guaranteed to exist for an agent
        // app, so it owns kicking off timers and the first fetch.
        .task { state.start() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // Agent app: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
