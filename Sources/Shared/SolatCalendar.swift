import Foundation

/// Date/time helpers pinned to the prayer dataset's timezone.
///
/// The waktusolat dataset describes Malaysian zones, so days must be bucketed in
/// `Asia/Kuala_Lumpur` (UTC+8, no DST). Doing this in the *system* timezone would
/// silently shift the day boundary — and therefore "today's prayers" — for anyone
/// travelling or running a Mac set to another region.
enum SolatCalendar {
    static let zoneTimeZone = TimeZone(identifier: "Asia/Kuala_Lumpur") ?? TimeZone(secondsFromGMT: 8 * 3600)!

    static var zoneCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zoneTimeZone
        cal.locale = Locale(identifier: "en_MY")
        return cal
    }()

    /// True when the Mac is not on Malaysian time, so the UI can say which
    /// timezone the listed times belong to.
    static var systemDiffersFromZone: Bool {
        TimeZone.current.secondsFromGMT() != zoneTimeZone.secondsFromGMT()
    }

    // MARK: Formatters

    /// `4:32 PM` or `16:32`, honouring the user's 24-hour preference.
    static func timeFormatter(use24Hour: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = zoneTimeZone
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f
    }

    static func dayFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = zoneTimeZone
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = format
        return f
    }

    static func string(for date: Date, use24Hour: Bool) -> String {
        timeFormatter(use24Hour: use24Hour).string(from: date)
    }

    /// `1h 12m`, `12m`, `just now` — used for the menu bar countdown.
    static func countdownString(until date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded(.up))
        if seconds <= 0 { return "now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Zero-padded `1:12:05` countdown for the popover header.
    static func preciseCountdownString(until date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Hijri

    /// Formats the dataset's `YYYY-MM-DD` Hijri string as e.g. `17 Safar 1448`.
    static func formatHijri(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month)
        else { return raw }
        let names = ["Muharram", "Safar", "Rabiulawal", "Rabiulakhir",
                     "Jamadilawal", "Jamadilakhir", "Rejab", "Syaaban",
                     "Ramadan", "Syawal", "Zulkaedah", "Zulhijjah"]
        return "\(day) \(names[month - 1]) \(parts[0])"
    }
}
