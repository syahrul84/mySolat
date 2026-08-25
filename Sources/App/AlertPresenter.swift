import AppKit
import SwiftUI

/// Shows the on-screen prayer popup and plays its sound.
///
/// Notification banners auto-hide after a few seconds, which is easy to miss.
/// This is a floating panel that stays put until dismissed (or until the
/// auto-dismiss timer runs out).
///
/// It's an `NSPanel` rather than a SwiftUI `Window` because it needs to:
///  - sit above other applications' windows, including full-screen ones,
///  - appear on whichever Space is active, and
///  - do all that *without* stealing keyboard focus from whatever the user is
///    typing in. `.nonactivatingPanel` is what buys that last part; the panel
///    still takes clicks, so Dismiss works without activating the app.
@MainActor
final class AlertPresenter: NSObject {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var sound: NSSound?

    /// Shows `alert`, replacing any popup already on screen.
    func present(_ alert: PrayerAlert,
                 zoneDescription: String,
                 prefs: Preferences,
                 onDismiss: (() -> Void)? = nil) {
        dismiss()

        let autoDismiss = prefs.popupAutoDismissSeconds
        let content = PrayerAlertView(
            alert: alert,
            zoneDescription: zoneDescription,
            use24Hour: prefs.use24HourClock,
            autoDismissAfter: autoDismiss
        ) { [weak self] in
            self?.dismiss()
            onDismiss?()
        }

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 190)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Above normal windows and full-screen apps, below the screen saver.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        playSound(prefs: prefs)

        if autoDismiss > 0 {
            let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoDismiss),
                                             repeats: false) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
            timer.tolerance = 1
            dismissTimer = timer
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        sound?.stop()
        sound = nil
        panel?.orderOut(nil)
        panel = nil
    }

    var isShowing: Bool { panel != nil }

    /// Plays the chosen sound. Used by the popup and by the settings preview.
    func playSound(prefs: Preferences) {
        guard prefs.notificationSoundEnabled,
              let name = prefs.alertSound.systemSoundName,
              let sound = NSSound(named: NSSound.Name(name))
        else { return }
        sound.stop()
        sound.play()
        self.sound = sound
    }

    /// Top-centre of the screen holding the pointer, tucked under the menu bar —
    /// close to where the menu bar item lives, and clear of most window content.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 12
        )
        panel.setFrameOrigin(origin)
    }
}
