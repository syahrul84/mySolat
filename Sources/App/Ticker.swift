import Combine
import Foundation

/// A periodic clock, published separately from `AppState`, and only running while
/// something actually needs it.
///
/// Two reasons this is its own object rather than a `@Published` date on
/// `AppState`:
///
/// 1. `AppState` is observed by the whole UI, including the settings window and
///    its 60-row zone list. Ticking there re-laid-out all of it every second.
/// 2. A tick redraws the menu bar item, and `NSStatusItem` replicates that draw
///    across every attached display. Ticking when no countdown is on screen is
///    pure waste.
///
/// Holders retain the ticker while they need it and release it when they go away,
/// so a closed popover costs nothing.
@MainActor
final class Ticker: ObservableObject {
    @Published private(set) var now = Date()

    private let interval: TimeInterval
    private var timer: Timer?
    private var holders = 0

    init(interval: TimeInterval) {
        self.interval = interval
    }

    deinit { timer?.invalidate() }

    var isRunning: Bool { timer != nil }

    /// Starts the clock if it wasn't already running.
    func retain() {
        holders += 1
        guard timer == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        // A generous tolerance lets the OS coalesce this with other timers instead
        // of waking the CPU on its own schedule.
        timer.tolerance = interval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the clock once the last holder lets go.
    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Convenience for views: retain while on screen, release when gone.
    func retained() -> Self {
        retain()
        return self
    }
}
