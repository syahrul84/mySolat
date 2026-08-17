import Foundation

// MARK: - Prayer

/// The eight time markers returned by the JAKIM/waktusolat dataset.
enum Prayer: String, CaseIterable, Codable, Identifiable, Sendable {
    case imsak, fajr, syuruk, dhuha, dhuhr, asr, maghrib, isha

    var id: String { rawValue }

    /// Malay name, as Malaysian users expect to read it.
    var displayName: String {
        switch self {
        case .imsak: return "Imsak"
        case .fajr: return "Subuh"
        case .syuruk: return "Syuruk"
        case .dhuha: return "Dhuha"
        case .dhuhr: return "Zohor"
        case .asr: return "Asar"
        case .maghrib: return "Maghrib"
        case .isha: return "Isyak"
        }
    }

    /// English/transliterated name, shown as a secondary label.
    var latinName: String {
        switch self {
        case .imsak: return "Imsak"
        case .fajr: return "Fajr"
        case .syuruk: return "Sunrise"
        case .dhuha: return "Dhuha"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }

    /// The five daily obligatory prayers. Imsak/Syuruk/Dhuha are informational
    /// markers, so they default to no notification.
    var isObligatory: Bool {
        switch self {
        case .fajr, .dhuhr, .asr, .maghrib, .isha: return true
        case .imsak, .syuruk, .dhuha: return false
        }
    }

    /// SF Symbol used in the popover and the widget.
    var symbolName: String {
        switch self {
        case .imsak: return "moon.stars"
        case .fajr: return "sunrise"
        case .syuruk: return "sun.horizon"
        case .dhuha: return "sun.min"
        case .dhuhr: return "sun.max"
        case .asr: return "sun.haze"
        case .maghrib: return "sunset"
        case .isha: return "moon"
        }
    }

    /// Order used for display: chronological within a day.
    static var displayOrder: [Prayer] {
        [.imsak, .fajr, .syuruk, .dhuha, .dhuhr, .asr, .maghrib, .isha]
    }
}

// MARK: - Zone

/// A JAKIM prayer-time zone, e.g. `SGR01` / Selangor / "Gombak, Petaling…".
struct Zone: Codable, Hashable, Identifiable, Sendable {
    let jakimCode: String
    let negeri: String
    let daerah: String

    var id: String { jakimCode }

    /// "SGR01 — Petaling, Gombak…"
    var label: String { "\(jakimCode) — \(daerah)" }

    /// Searchable haystack for the zone picker.
    var searchText: String { "\(jakimCode) \(negeri) \(daerah)".lowercased() }
}

// MARK: - API response shapes

/// `GET /v2/solat/{zone}` — one calendar month of prayer times.
struct MonthlyPrayerResponse: Codable, Sendable {
    let zone: String
    let year: Int
    let month: String
    let monthNumber: Int
    let prayers: [APIDayPrayers]

    enum CodingKeys: String, CodingKey {
        case zone, year, month, prayers
        case monthNumber = "month_number"
    }
}

/// One day inside a `MonthlyPrayerResponse`. All times are UNIX timestamps.
struct APIDayPrayers: Codable, Sendable {
    let day: Int
    let hijri: String?
    let imsak: TimeInterval?
    let fajr: TimeInterval?
    let syuruk: TimeInterval?
    let dhuha: TimeInterval?
    let dhuhr: TimeInterval?
    let asr: TimeInterval?
    let maghrib: TimeInterval?
    let isha: TimeInterval?

    func timestamp(for prayer: Prayer) -> TimeInterval? {
        switch prayer {
        case .imsak: return imsak
        case .fajr: return fajr
        case .syuruk: return syuruk
        case .dhuha: return dhuha
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }
}

/// `GET /v2/solat/gps/{lat}/{long}` — zone detection payload. The API has
/// changed shape across versions, so every field is treated as optional and we
/// take whichever zone code is present.
struct GPSZoneResponse: Codable, Sendable {
    let zone: String?
    let negeri: String?
    let daerah: String?
    let jakimCode: String?

    var resolvedZoneCode: String? { zone ?? jakimCode }
}

// MARK: - Stored model

/// One day of prayer times, flattened for storage and display.
///
/// Times are keyed by `Prayer.rawValue` so the on-disk JSON stays readable and
/// forward-compatible if the upstream dataset gains a marker.
struct PrayerDay: Codable, Hashable, Identifiable, Sendable {
    /// Midnight of this day in the zone's timezone.
    let date: Date
    let hijri: String?
    let times: [String: Date]

    var id: Date { date }

    func time(for prayer: Prayer) -> Date? { times[prayer.rawValue] }

    /// Chronological list of the markers that actually have a time.
    var events: [PrayerEvent] {
        Prayer.displayOrder.compactMap { prayer in
            guard let date = time(for: prayer) else { return nil }
            return PrayerEvent(prayer: prayer, date: date)
        }
    }
}

/// A single prayer at a concrete instant.
struct PrayerEvent: Hashable, Identifiable, Sendable {
    let prayer: Prayer
    let date: Date

    var id: String { "\(prayer.rawValue)-\(date.timeIntervalSince1970)" }
}

/// The cached prayer schedule for one zone, persisted to the shared container.
struct PrayerCache: Codable, Sendable {
    var zone: String
    var days: [PrayerDay]
    var fetchedAt: Date

    static func empty(zone: String) -> PrayerCache {
        PrayerCache(zone: zone, days: [], fetchedAt: .distantPast)
    }

    /// Last day covered by the cache, used to decide whether to refetch.
    var lastCoveredDay: Date? { days.map(\.date).max() }

    /// How many whole days of coverage remain from `reference` onward.
    func coverageDays(from reference: Date = Date()) -> Int {
        let cal = SolatCalendar.zoneCalendar
        let today = cal.startOfDay(for: reference)
        guard let last = lastCoveredDay else { return 0 }
        let comps = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: last))
        return max(0, (comps.day ?? 0) + 1)
    }

    func day(containing reference: Date) -> PrayerDay? {
        let target = SolatCalendar.zoneCalendar.startOfDay(for: reference)
        return days.first { $0.date == target }
    }

    /// Every prayer event at or after `reference`, in chronological order.
    func upcomingEvents(from reference: Date = Date()) -> [PrayerEvent] {
        days.flatMap(\.events)
            .filter { $0.date >= reference }
            .sorted { $0.date < $1.date }
    }
}
