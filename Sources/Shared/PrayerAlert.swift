import Foundation

/// A macOS system sound, chosen for the popup.
///
/// These ship with every Mac in `/System/Library/Sounds`, so nothing needs
/// bundling and each is instantly familiar.
enum AlertSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case glass = "Glass"
    case ping = "Ping"
    case blow = "Blow"
    case bottle = "Bottle"
    case funk = "Funk"
    case hero = "Hero"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }

    var displayName: String { self == .none ? "No sound" : rawValue }

    /// The name `NSSound(named:)` expects, or nil for silence.
    var systemSoundName: String? { self == .none ? nil : rawValue }
}

/// Which of the two moments an alert marks.
enum PrayerAlertKind: String, Codable, Sendable {
    /// Fired `preAlertMinutes` before the prayer, to give time to prepare.
    case beforePrayer
    /// Fired the moment the prayer time enters.
    case atPrayerTime
}

/// A single alert to raise at a specific instant.
struct PrayerAlert: Identifiable, Hashable, Sendable {
    let prayer: Prayer
    /// When the prayer itself begins.
    let prayerDate: Date
    /// When this alert should fire — equals `prayerDate` for `.atPrayerTime`.
    let fireDate: Date
    let kind: PrayerAlertKind
    /// Minutes of warning, for the `.beforePrayer` wording.
    let minutesBefore: Int

    /// Stable across relaunches so an alert is never replayed.
    var id: String {
        let stamp = SolatCalendar.dayFormatter("yyyyMMdd").string(from: prayerDate)
        return "\(prayer.rawValue).\(stamp).\(kind.rawValue)"
    }

    var title: String {
        switch kind {
        case .atPrayerTime:
            return "\(prayer.displayName) has entered"
        case .beforePrayer:
            return "\(prayer.displayName) in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")"
        }
    }
}

/// Decides which alerts are due. Pure and side-effect free so it can be tested
/// without a running app.
enum PrayerAlertScheduler {
    /// Default catch-up window: how late an alert may still be worth showing.
    ///
    /// Popups are suppressed while the Mac is asleep or locked, so on unlock we
    /// can be well past a prayer. Subuh at 6:00 is still worth surfacing if the
    /// user sits down at 6:20; showing it at noon would be worse than useless.
    static let defaultCatchUpWindow: TimeInterval = 30 * 60

    /// Builds the alert list for the given events and settings.
    ///
    /// Includes alerts whose moment has already passed; `due(from:now:already:)`
    /// applies the timing rules.
    static func alerts(for events: [PrayerEvent], prefs: Preferences) -> [PrayerAlert] {
        let enabled = prefs.enabledPrayers
        var result: [PrayerAlert] = []

        for event in events where enabled.contains(event.prayer) {
            if prefs.popupBeforePrayer || prefs.preAlertEnabled {
                let minutes = prefs.preAlertMinutes
                result.append(PrayerAlert(
                    prayer: event.prayer,
                    prayerDate: event.date,
                    fireDate: event.date.addingTimeInterval(-Double(minutes) * 60),
                    kind: .beforePrayer,
                    minutesBefore: minutes
                ))
            }
            if prefs.popupAtPrayerTime || prefs.notifyAtPrayerTime {
                result.append(PrayerAlert(
                    prayer: event.prayer,
                    prayerDate: event.date,
                    fireDate: event.date,
                    kind: .atPrayerTime,
                    minutesBefore: 0
                ))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// The alerts that should fire right now: due, not stale, not already shown.
    /// - Parameter window: how late an alert may be and still show. Pass 0 to
    ///   suppress catch-up entirely, so only alerts firing right now appear.
    static func due(from alerts: [PrayerAlert],
                    now: Date,
                    already: Set<String>,
                    window: TimeInterval = defaultCatchUpWindow) -> [PrayerAlert] {
        alerts.filter { alert in
            guard !already.contains(alert.id) else { return false }
            let late = now.timeIntervalSince(alert.fireDate)
            return late >= 0 && late <= window
        }
    }

    /// The single alert worth showing out of everything currently due.
    ///
    /// After a stretch asleep, several can come due at once — the pre-alert *and*
    /// the prayer itself. The latest one is the truthful one: announcing "Subuh in
    /// 15 minutes" when Subuh has already entered would be plainly wrong.
    static func mostRelevant(from alerts: [PrayerAlert],
                             now: Date,
                             already: Set<String>,
                             window: TimeInterval = defaultCatchUpWindow) -> PrayerAlert? {
        due(from: alerts, now: now, already: already, window: window).last
    }

    /// How many days of fired-alert ids to keep.
    ///
    /// Ids encode their day, so anything older than the alerts we still evaluate
    /// can never match again. Three days is comfortably beyond the longest
    /// catch-up window.
    static let firedIDRetentionDays = 3

    /// Drops fired-alert ids for days already behind us.
    ///
    /// This must prune by *date*, never by a count: ids sort by prayer name
    /// first, so trimming a sorted list drops whole prayers — `asr` before
    /// everything else — rather than the oldest entries.
    static func pruneFiredIDs(_ ids: Set<String>,
                              now: Date = Date(),
                              days: Int = firedIDRetentionDays) -> Set<String> {
        let cal = SolatCalendar.zoneCalendar
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: now) else { return ids }
        let cutoffStamp = SolatCalendar.dayFormatter("yyyyMMdd").string(from: cutoff)
        return ids.filter { id in
            let parts = id.split(separator: ".")
            // Unrecognised shapes are kept: better a stale id than a repeat alert.
            guard parts.count >= 2 else { return true }
            let stamp = String(parts[1])
            guard stamp.count == 8, stamp.allSatisfy(\.isNumber) else { return true }
            return stamp >= cutoffStamp
        }
    }

    /// Alerts whose moment passed while the app wasn't watching and which are now
    /// too stale to show. Marked as fired so they don't surface later.
    static func expired(from alerts: [PrayerAlert],
                        now: Date,
                        already: Set<String>,
                        window: TimeInterval = defaultCatchUpWindow) -> [PrayerAlert] {
        alerts.filter { alert in
            guard !already.contains(alert.id) else { return false }
            return now.timeIntervalSince(alert.fireDate) > window
        }
    }
}
