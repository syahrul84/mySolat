import AppKit
import CoreGraphics
import Foundation

/// Tracks whether the user is actually at the machine and able to see a popup.
///
/// "Active" means the session is unlocked, the displays are awake, and no screen
/// saver is running. Firing a popup — and its sound — at a locked or closed
/// laptop is worse than useless: the user never sees it, and the alert is then
/// treated as delivered.
///
/// macOS signals these states through three different channels, so all three are
/// observed:
///  - lock/unlock via `DistributedNotificationCenter` (`com.apple.screenIsLocked`),
///  - display sleep/wake and system sleep/wake via `NSWorkspace`,
///  - screen saver start/stop, also distributed.
@MainActor
final class ScreenActivityMonitor {
    /// Called when the machine goes from unavailable to available, so missed
    /// alerts can be reconsidered.
    var onBecameActive: (() -> Void)?

    private(set) var isActive: Bool = true

    private var screensAsleep = false
    private var systemAsleep = false
    private var screenSaverRunning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        screensAsleep = Self.displaysAreAsleep()
        recomputeActive(notify: false)
        observe()
    }

    deinit {
        // Captured to avoid touching main-actor state from deinit.
        let tokens = observers
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for token in tokens {
            workspace.removeObserver(token)
            distributed.removeObserver(token)
        }
    }

    // MARK: Current state

    /// True when the login session is locked (or fast-user-switched away).
    static func sessionIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = info["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        if let onConsole = info["kCGSSessionOnConsoleKey"] as? Bool, !onConsole { return true }
        return false
    }

    static func displaysAreAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    // MARK: Observation

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func onWorkspace(_ name: NSNotification.Name, _ handler: @escaping () -> Void) {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in handler() }
            })
        }
        func onDistributed(_ name: String, _ handler: @escaping () -> Void) {
            observers.append(distributed.addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main
            ) { _ in
                Task { @MainActor in handler() }
            })
        }

        onWorkspace(NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.screensAsleep = true; self?.recomputeActive()
        }
        onWorkspace(NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.screensAsleep = false; self?.recomputeActive()
        }
        onWorkspace(NSWorkspace.willSleepNotification) { [weak self] in
            self?.systemAsleep = true; self?.recomputeActive()
        }
        onWorkspace(NSWorkspace.didWakeNotification) { [weak self] in
            self?.systemAsleep = false; self?.recomputeActive()
        }
        onWorkspace(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.recomputeActive()
        }
        onWorkspace(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.recomputeActive()
        }

        onDistributed("com.apple.screenIsLocked") { [weak self] in self?.recomputeActive() }
        onDistributed("com.apple.screenIsUnlocked") { [weak self] in self?.recomputeActive() }
        onDistributed("com.apple.screensaver.didstart") { [weak self] in
            self?.screenSaverRunning = true; self?.recomputeActive()
        }
        onDistributed("com.apple.screensaver.didstop") { [weak self] in
            self?.screenSaverRunning = false; self?.recomputeActive()
        }
    }

    /// Re-evaluates availability, firing `onBecameActive` on a rising edge.
    ///
    /// Lock state is queried rather than tracked, because the distributed
    /// notifications can be missed (they don't queue while the app is suspended).
    func recomputeActive(notify: Bool = true) {
        // Both the tracked flag and a live query: the notification can arrive
        // before `CGDisplayIsAsleep` flips, and the query catches a sleep that
        // happened while the app wasn't observing.
        let displaysOff = screensAsleep || Self.displaysAreAsleep()
        let active = !Self.sessionIsLocked()
            && !screenSaverRunning
            && !systemAsleep
            && !displaysOff

        let wasActive = isActive
        isActive = active

        if notify, active, !wasActive {
            onBecameActive?()
        }
    }
}
