import Foundation
import WidgetKit

/// The value a widget timeline hands to the views.
///
/// Kept apart from `SolatWidget.swift` so tooling can build the widget views
/// without pulling in that file's `@main` entry point — two `@main` types in one
/// module produce duplicate `_main` symbols.
struct PrayerEntry: TimelineEntry {
    let date: Date
    let day: PrayerDay?
    let next: PrayerEvent?
    let zoneDescription: String
    let hijri: String?
    let use24Hour: Bool
    let visiblePrayers: [Prayer]
    let isPlaceholder: Bool

    static func placeholder(now: Date = Date()) -> PrayerEntry {
        PrayerEntry(
            date: now,
            day: nil,
            next: nil,
            zoneDescription: "Open mySolat",
            hijri: nil,
            use24Hour: false,
            visiblePrayers: Prayer.displayOrder.filter(\.isObligatory),
            isPlaceholder: true
        )
    }

    /// Representative entry used for the widget gallery preview.
    ///
    /// WidgetKit renders `placeholder(in:)` as a redacted skeleton, so returning an
    /// empty entry makes the gallery show blank bars. Filling it with plausible
    /// times gives the preview the shape of a real prayer list instead.
    static func sample(now: Date = Date()) -> PrayerEntry {
        let cal = SolatCalendar.zoneCalendar
        let dayStart = cal.startOfDay(for: now)

        // Typical Klang Valley times, rounded — preview only, never displayed as fact.
        let offsets: [(Prayer, Int, Int)] = [
            (.imsak, 5, 51), (.fajr, 6, 1), (.syuruk, 7, 10), (.dhuha, 7, 35),
            (.dhuhr, 13, 20), (.asr, 16, 36), (.maghrib, 19, 26), (.isha, 20, 37),
        ]
        var times: [String: Date] = [:]
        for (prayer, hour, minute) in offsets {
            times[prayer.rawValue] = cal.date(byAdding: DateComponents(hour: hour, minute: minute),
                                              to: dayStart)
        }
        let day = PrayerDay(date: dayStart, hijri: "1448-03-04", times: times)
        let next = day.events.first { $0.date > now } ?? day.events.last

        return PrayerEntry(
            date: now,
            day: day,
            next: next,
            zoneDescription: "Gombak, Petaling, Sepang",
            hijri: SolatCalendar.formatHijri(day.hijri),
            use24Hour: false,
            visiblePrayers: Prayer.displayOrder,
            isPlaceholder: true
        )
    }
}
