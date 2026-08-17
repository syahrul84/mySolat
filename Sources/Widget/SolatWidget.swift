import SwiftUI
import WidgetKit

@main
struct SolatWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrayerTimesWidget()
    }
}

struct PrayerTimesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppIdentifiers.widgetKind, provider: PrayerTimelineProvider()) { entry in
            PrayerWidgetView(entry: entry)
                .solatWidgetBackground()
        }
        .configurationDisplayName("Prayer Times")
        .description("Malaysian prayer times for your zone. Set the zone in mySolat's settings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

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
}

/// Feeds the widget from the shared cache.
///
/// The widget is sandboxed and cannot reach the app's Application Support folder,
/// so it reads the App Group container. If that comes back empty — which happens
/// on ad-hoc-signed builds without a provisioned group — it falls back to fetching
/// the current month straight from the API so the widget still shows real times.
struct PrayerTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        Task { completion(await makeEntry(for: Date())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = await makeEntry(for: now)

            // Refresh exactly when the next prayer enters, so the highlighted row
            // and countdown never go stale — capped so WidgetKit still gets a
            // reload at least every couple of hours.
            let cap = now.addingTimeInterval(2 * 60 * 60)
            let nextBoundary = entry.next?.date.addingTimeInterval(1) ?? cap
            let refresh = min(nextBoundary, cap)

            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func makeEntry(for now: Date) async -> PrayerEntry {
        let prefs = Preferences()
        var cache = PrayerCacheFile.load()

        // Nothing shared with us — fetch directly rather than showing an empty box.
        if cache == nil || cache?.day(containing: now) == nil {
            cache = await fetchDirect(zone: prefs.zoneCode, now: now) ?? cache
        }

        guard let cache, let day = cache.day(containing: now) else {
            return .placeholder(now: now)
        }

        let next = cache.upcomingEvents(from: now).first
        return PrayerEntry(
            date: now,
            day: day,
            next: next,
            zoneDescription: ZoneCatalog.shared.describe(code: cache.zone),
            hijri: SolatCalendar.formatHijri(day.hijri),
            use24Hour: prefs.use24HourClock,
            visiblePrayers: prefs.visiblePrayers,
            isPlaceholder: false
        )
    }

    /// Best-effort direct fetch. Never throws — the widget degrades to a
    /// placeholder instead of erroring.
    private func fetchDirect(zone: String, now: Date) async -> PrayerCache? {
        let api = WaktuSolatAPI(session: WaktuSolatAPI.makeDefaultSession())
        let cal = SolatCalendar.zoneCalendar
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else { return nil }
        do {
            let response = try await api.fetchMonth(zone: zone, year: year, month: month)
            let days = response.toPrayerDays()
            guard !days.isEmpty else { return nil }
            return PrayerCache(zone: zone, days: days, fetchedAt: Date())
        } catch {
            return nil
        }
    }
}
