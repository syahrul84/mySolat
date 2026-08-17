import Foundation
import UserNotifications

/// Schedules the "prayer time has entered" and "prayer in N minutes" alerts.
///
/// ## Why a rolling window
/// macOS keeps at most 64 *pending* notification requests per app. With 5 prayers
/// and both alert kinds enabled that's 10 requests a day, so scheduling a full
/// month up front would silently drop most of it. Instead we schedule as many
/// whole days as fit under `requestBudget` and re-schedule regularly (hourly, on
/// wake, on launch, and whenever settings change). The *prayer data* is still
/// cached 30+ days ahead — only the OS-level alerts roll forward.
@MainActor
final class NotificationScheduler {
    /// Stay under the 64-request ceiling, leaving room for a few ad-hoc alerts.
    private static let requestBudget = 58

    private let center = UNUserNotificationCenter.current()
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var lastScheduledCount = 0
    private(set) var lastScheduledThrough: Date?

    // MARK: Authorization

    /// Asks for permission the first time; afterwards just refreshes the cached
    /// status. Returns true when we're allowed to post alerts.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationStatus()
                return granted
            } catch {
                return false
            }
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: Scheduling

    /// Replaces all pending prayer alerts with a fresh rolling window.
    ///
    /// - Parameters:
    ///   - events: upcoming prayer events, chronological, from the cache.
    ///   - prefs: current user settings.
    ///   - zoneDescription: shown in the notification body, e.g. "Gombak, Selangor".
    func reschedule(events: [PrayerEvent],
                    prefs: Preferences,
                    zoneDescription: String,
                    now: Date = Date()) async {
        center.removeAllPendingNotificationRequests()
        lastScheduledCount = 0
        lastScheduledThrough = nil

        guard isAuthorized else { return }

        let enabled = prefs.enabledPrayers
        guard !enabled.isEmpty, prefs.notifyAtPrayerTime || prefs.preAlertEnabled else { return }

        var requests: [UNNotificationRequest] = []

        for event in events where enabled.contains(event.prayer) {
            if requests.count >= Self.requestBudget { break }

            // Pre-alert: only worth scheduling if it hasn't already passed.
            if prefs.preAlertEnabled {
                let alertDate = event.date.addingTimeInterval(-Double(prefs.preAlertMinutes) * 60)
                if alertDate > now, requests.count < Self.requestBudget {
                    requests.append(makeRequest(
                        for: event,
                        fireAt: alertDate,
                        kind: .preAlert(minutes: prefs.preAlertMinutes),
                        prefs: prefs,
                        zoneDescription: zoneDescription
                    ))
                }
            }

            if prefs.notifyAtPrayerTime, event.date > now, requests.count < Self.requestBudget {
                requests.append(makeRequest(
                    for: event,
                    fireAt: event.date,
                    kind: .onTime,
                    prefs: prefs,
                    zoneDescription: zoneDescription
                ))
            }
        }

        for request in requests {
            try? await center.add(request)
        }

        lastScheduledCount = requests.count
        lastScheduledThrough = requests.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }.max()
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        lastScheduledCount = 0
        lastScheduledThrough = nil
    }

    /// Posts an immediate test alert so the user can confirm the setup works.
    func sendTestNotification(prefs: Preferences) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "mySolat notifications are working"
        content.body = prefs.preAlertEnabled
            ? "You'll be alerted \(prefs.preAlertMinutes) minute\(prefs.preAlertMinutes == 1 ? "" : "s") before each prayer, and again when the time enters."
            : "You'll be alerted when each prayer time enters."
        if prefs.notificationSoundEnabled { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "mySolat-test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    // MARK: Request building

    private enum AlertKind {
        case preAlert(minutes: Int)
        case onTime

        var suffix: String {
            switch self {
            case .preAlert: return "pre"
            case .onTime: return "at"
            }
        }
    }

    private func makeRequest(for event: PrayerEvent,
                             fireAt: Date,
                             kind: AlertKind,
                             prefs: Preferences,
                             zoneDescription: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let timeString = SolatCalendar.string(for: event.date, use24Hour: prefs.use24HourClock)

        switch kind {
        case .onTime:
            content.title = "\(event.prayer.displayName) — \(timeString)"
            content.body = event.prayer.isObligatory
                ? "It's time for \(event.prayer.displayName) in \(zoneDescription)."
                : "\(event.prayer.displayName) has entered in \(zoneDescription)."
            content.interruptionLevel = .timeSensitive
        case .preAlert(let minutes):
            content.title = "\(event.prayer.displayName) in \(minutes) minute\(minutes == 1 ? "" : "s")"
            content.body = "\(event.prayer.displayName) begins at \(timeString) in \(zoneDescription)."
            content.interruptionLevel = .active
        }

        if prefs.notificationSoundEnabled { content.sound = .default }
        content.threadIdentifier = "mySolat.\(event.prayer.rawValue)"
        content.userInfo = [
            "prayer": event.prayer.rawValue,
            "prayerDate": event.date.timeIntervalSince1970,
        ]

        // Absolute one-shot trigger: year-qualified components in the dataset's
        // timezone, so a system timezone change can't shift the fire time.
        var comps = SolatCalendar.zoneCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireAt
        )
        comps.timeZone = SolatCalendar.zoneTimeZone

        return UNNotificationRequest(
            identifier: identifier(for: event, kind: kind),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
    }

    private func identifier(for event: PrayerEvent, kind: AlertKind) -> String {
        let stamp = SolatCalendar.dayFormatter("yyyyMMdd").string(from: event.date)
        return "mySolat.\(event.prayer.rawValue).\(stamp).\(kind.suffix)"
    }
}

/// Keeps banners visible even while mySolat is the active app.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
