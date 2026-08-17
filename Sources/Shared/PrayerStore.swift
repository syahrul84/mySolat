import Foundation

/// Loads, caches and serves prayer times, keeping at least `minimumCoverageDays`
/// of schedule on disk so the app works fully offline.
///
/// The upstream API is month-granular, so coverage is built by fetching whole
/// calendar months: enough consecutive months to cover today + 35 days. That means
/// 2 months normally and 3 near a month boundary — a handful of small requests,
/// done once, then reused from disk until the window shrinks.
actor PrayerStore {
    /// The app guarantees at least 30 days ahead; we target 35 for headroom so a
    /// Mac left asleep for a few days still has a full month buffered on wake.
    static let minimumCoverageDays = 30
    static let targetCoverageDays = 35

    private let api: WaktuSolatAPI
    private var cache: PrayerCache

    init(api: WaktuSolatAPI = WaktuSolatAPI(session: WaktuSolatAPI.makeDefaultSession()),
         zone: String) {
        self.api = api
        // Only adopt the cached schedule when it belongs to the requested zone.
        // Otherwise the app would serve another zone's times under this zone's
        // name — the UI labels rows from the preference, not from the cache.
        // Happens whenever the zone preference and the cache fall out of step.
        if let disk = PrayerCacheFile.load(), disk.zone.caseInsensitiveCompare(zone) == .orderedSame {
            self.cache = disk
        } else {
            self.cache = .empty(zone: zone)
        }
    }

    // MARK: Reads

    var currentCache: PrayerCache { cache }

    var coverageDays: Int { cache.coverageDays() }

    var needsRefresh: Bool { cache.coverageDays() < Self.minimumCoverageDays }

    func today(now: Date = Date()) -> PrayerDay? { cache.day(containing: now) }

    func upcomingEvents(from now: Date = Date(), limit: Int? = nil) -> [PrayerEvent] {
        let events = cache.upcomingEvents(from: now)
        guard let limit else { return events }
        return Array(events.prefix(limit))
    }

    /// The next prayer at or after `now`, restricted to `prayers` when given.
    func nextEvent(from now: Date = Date(), among prayers: Set<Prayer>? = nil) -> PrayerEvent? {
        cache.upcomingEvents(from: now).first { event in
            guard let prayers else { return true }
            return prayers.contains(event.prayer)
        }
    }

    /// The prayer period the user is currently inside — the most recent event that
    /// has already started today.
    func currentEvent(now: Date = Date()) -> PrayerEvent? {
        guard let day = cache.day(containing: now) else { return nil }
        return day.events.filter { $0.date <= now }.last
    }

    func days(from now: Date = Date(), count: Int) -> [PrayerDay] {
        let today = SolatCalendar.zoneCalendar.startOfDay(for: now)
        return cache.days
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
            .prefix(count)
            .map { $0 }
    }

    // MARK: Writes

    /// Switches zone and discards the old schedule, forcing a refetch.
    func setZone(_ zone: String) {
        guard cache.zone.caseInsensitiveCompare(zone) != .orderedSame else { return }
        cache = .empty(zone: zone)
        try? PrayerCacheFile.save(cache)
    }

    /// Ensures the cache covers `targetCoverageDays` from today.
    ///
    /// - Parameter force: refetch even when coverage already looks sufficient,
    ///   used by the manual "Refresh now" action.
    /// - Returns: the refreshed cache.
    /// - Throws: the last network/decoding error, but only when the refresh
    ///   produced no usable data at all. A partial success is kept silently.
    @discardableResult
    func refresh(force: Bool = false, now: Date = Date()) async throws -> PrayerCache {
        if !force, cache.coverageDays(from: now) >= Self.minimumCoverageDays {
            return cache
        }

        let months = Self.monthsToCover(from: now, days: Self.targetCoverageDays)
        var collected: [Date: PrayerDay] = [:]
        var lastError: Error?

        // Seed with what we already have so a single failed month doesn't wipe
        // out a schedule the user could still be reading offline.
        for day in cache.days { collected[day.date] = day }

        for month in months {
            do {
                let response = try await api.fetchMonth(zone: cache.zone, year: month.year, month: month.month)
                for day in response.toPrayerDays() { collected[day.date] = day }
            } catch {
                lastError = error
            }
        }

        let today = SolatCalendar.zoneCalendar.startOfDay(for: now)
        // Keep yesterday onward: "today" in the zone can still be yesterday for a
        // user west of Malaysia, and it costs one row.
        let cutoff = SolatCalendar.zoneCalendar.date(byAdding: .day, value: -1, to: today) ?? today
        let pruned = collected.values
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }

        guard !pruned.isEmpty else {
            throw lastError ?? SolatAPIError.badResponse(status: -1)
        }

        cache = PrayerCache(zone: cache.zone, days: pruned, fetchedAt: Date())
        try? PrayerCacheFile.save(cache)

        // Surface the error only if we still fell short of the guarantee.
        if let lastError, cache.coverageDays(from: now) < Self.minimumCoverageDays {
            throw lastError
        }
        return cache
    }

    /// Reloads from disk — used by the widget and after an external write.
    ///
    /// Guards on zone for the same reason `init` does: a cache for a different zone
    /// must never be adopted silently.
    func reloadFromDisk() {
        guard let disk = PrayerCacheFile.load(),
              disk.zone.caseInsensitiveCompare(cache.zone) == .orderedSame,
              disk.fetchedAt >= cache.fetchedAt
        else { return }
        cache = disk
    }

    // MARK: Helpers

    /// The (year, month) pairs needed to cover `days` ahead of `from`.
    static func monthsToCover(from date: Date, days: Int) -> [(year: Int, month: Int)] {
        let cal = SolatCalendar.zoneCalendar
        let end = cal.date(byAdding: .day, value: days, to: date) ?? date
        var result: [(year: Int, month: Int)] = []
        var cursor = cal.startOfDay(for: date)

        while cursor <= end {
            let comps = cal.dateComponents([.year, .month], from: cursor)
            if let year = comps.year, let month = comps.month,
               !result.contains(where: { $0.year == year && $0.month == month }) {
                result.append((year: year, month: month))
            }
            guard let nextMonth = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = cal.date(from: cal.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        }
        return result
    }
}
