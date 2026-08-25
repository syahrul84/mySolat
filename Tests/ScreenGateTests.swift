import AppKit

// The screen-activity gate needs AppKit notifications, so it lives in its own
// harness target rather than the plain test binary. Run via `make test-gate`.

@main
enum ScreenGateTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let monitor = ScreenActivityMonitor()
        var becameActiveCount = 0
        monitor.onBecameActive = { becameActiveCount += 1 }

        var failures = 0
        var checks = 0
        func check(_ cond: Bool, _ label: String) {
            checks += 1
            print(cond ? "  \u{2713} \(label)" : "  \u{2717} \(label)")
            if !cond { failures += 1 }
        }

        let wc = NSWorkspace.shared.notificationCenter
        func post(_ n: NSNotification.Name) {
            wc.post(name: n, object: nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        print("Screen-activity gate")

        check(monitor.isActive, "starts active on an awake, unlocked Mac")

        post(NSWorkspace.screensDidSleepNotification)
        check(!monitor.isActive, "display sleep closes the gate")

        let before = becameActiveCount
        post(NSWorkspace.screensDidWakeNotification)
        check(monitor.isActive, "display wake reopens the gate")
        check(becameActiveCount == before + 1, "wake fires onBecameActive exactly once")

        post(NSWorkspace.willSleepNotification)
        check(!monitor.isActive, "system sleep closes the gate")
        post(NSWorkspace.screensDidSleepNotification)
        check(!monitor.isActive, "still closed with both sleep signals")

        // Waking the display alone must not reopen it while the system is asleep.
        post(NSWorkspace.screensDidWakeNotification)
        check(!monitor.isActive, "display wake alone does not reopen during system sleep")

        let before2 = becameActiveCount
        post(NSWorkspace.didWakeNotification)
        check(monitor.isActive, "system wake reopens the gate")
        check(becameActiveCount == before2 + 1, "one onBecameActive per rising edge")

        // No spurious callbacks while already active.
        let before3 = becameActiveCount
        post(NSWorkspace.didWakeNotification)
        check(becameActiveCount == before3, "no callback when already active")

        
        print("")
        if failures == 0 {
            print("\u{2713} all \(checks) gate checks passed")
            exit(0)
        } else {
            print("\u{2717} \(failures) of \(checks) gate checks failed")
            exit(1)
        }
    }
}
