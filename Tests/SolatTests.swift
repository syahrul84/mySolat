import Foundation

// A plain executable test harness rather than XCTest: XCTest needs a full Xcode
// install, and mySolat is built with the Command Line Tools alone. Run `make test`.

// MARK: - Tiny assertion framework

private var failures: [String] = []
private var checks = 0

private func check(_ condition: Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if condition {
        print("  ✓ \(label)")
    } else {
        print("  ✗ \(label)  (line \(line))")
        failures.append(label)
    }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
    checks += 1
    if actual == expected {
        print("  ✓ \(label)")
    } else {
        print("  ✗ \(label)\n      expected: \(expected)\n      actual:   \(actual)  (line \(line))")
        failures.append(label)
    }
}

private func section(_ name: String) {
    print("\n\(name)")
}

// MARK: - Version comparison

func testVersionComparison() {
    section("AppVersion.isNewer")
    check(AppVersion.isNewer("1.0.1", than: "1.0.0"), "patch bump is newer")
    check(AppVersion.isNewer("1.1.0", than: "1.0.9"), "minor beats patch")
    check(AppVersion.isNewer("2.0.0", than: "1.9.9"), "major beats minor")
    check(AppVersion.isNewer("v1.2.0", than: "1.1.0"), "leading v tolerated")
    check(AppVersion.isNewer("1.2", than: "1.1.9"), "short form compares")
    check(AppVersion.isNewer("1.10.0", than: "1.9.0"), "10 > 9 numerically, not lexically")
    check(!AppVersion.isNewer("1.0.0", than: "1.0.0"), "equal is not newer")
    check(!AppVersion.isNewer("1.0.0", than: "1.0.1"), "older is not newer")
    check(!AppVersion.isNewer("1.0.0-beta.1", than: "1.0.0"), "pre-release core equal is not newer")
    checkEqual(AppVersion.compare("1.0.0", "1.0.0"), .orderedSame, "identical compares same")
}

// MARK: - Month coverage planning

func testMonthsToCover() {
    section("PrayerStore.monthsToCover")
    let cal = SolatCalendar.zoneCalendar

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        c.timeZone = SolatCalendar.zoneTimeZone
        return cal.date(from: c)!
    }

    // Mid-month: 35 days ahead spills into the next month only.
    let mid = PrayerStore.monthsToCover(from: date(2026, 8, 10), days: 35)
    checkEqual(mid.count, 2, "mid-August needs 2 months")
    checkEqual(mid.first?.month, 8, "starts in August")
    checkEqual(mid.last?.month, 9, "ends in September")

    // End of month: spills across three months.
    let late = PrayerStore.monthsToCover(from: date(2026, 8, 30), days: 35)
    checkEqual(late.count, 3, "30 August needs 3 months")
    checkEqual(late.map(\.month), [8, 9, 10], "August → October")

    // Year boundary.
    let yearEnd = PrayerStore.monthsToCover(from: date(2026, 12, 20), days: 35)
    checkEqual(yearEnd.count, 2, "late December needs 2 months")
    checkEqual(yearEnd.first!.year, 2026, "first month is 2026")
    checkEqual(yearEnd.last!.year, 2027, "rolls into 2027")
    checkEqual(yearEnd.last!.month, 1, "rolls into January")

    // Leap-year February.
    let feb = PrayerStore.monthsToCover(from: date(2028, 2, 1), days: 35)
    checkEqual(feb.map(\.month), [2, 3], "leap February → March")
}

// MARK: - API decoding

func testResponseDecoding() {
    section("MonthlyPrayerResponse → PrayerDay")

    // Real payload shape from GET /v2/solat/SGR01 (trimmed to two days).
    let json = """
    {
      "zone": "SGR01",
      "year": 2026,
      "month": "AUG",
      "month_number": 8,
      "last_updated": null,
      "prayers": [
        {"day":1,"hijri":"1448-02-17","imsak":1785534660,"fajr":1785535260,
         "syuruk":1785539460,"dhuha":1785540960,"dhuhr":1785561720,
         "asr":1785573780,"maghrib":1785583800,"isha":1785588120},
        {"day":2,"hijri":"1448-02-18","imsak":1785621060,"fajr":1785621660,
         "syuruk":1785625860,"dhuha":1785627360,"dhuhr":1785648120,
         "asr":1785660180,"maghrib":1785670200,"isha":1785674520}
      ]
    }
    """.data(using: .utf8)!

    guard let response = try? JSONDecoder().decode(MonthlyPrayerResponse.self, from: json) else {
        check(false, "response decodes")
        return
    }
    check(true, "response decodes")
    checkEqual(response.zone, "SGR01", "zone parsed")
    checkEqual(response.monthNumber, 8, "month_number mapped from snake_case")

    let days = response.toPrayerDays()
    checkEqual(days.count, 2, "two days flattened")

    guard let first = days.first else { return }
    checkEqual(first.times.count, 8, "all eight markers stored")
    checkEqual(first.hijri, "1448-02-17", "hijri retained")

    // Verify a known instant renders as the expected Malaysian wall-clock time.
    // 1785535260 = 2026-08-16 06:01 MYT (Subuh).
    let fajr = first.time(for: .fajr)
    check(fajr != nil, "fajr present")
    if let fajr {
        checkEqual(SolatCalendar.string(for: fajr, use24Hour: true), "06:01", "fajr renders as 06:01 MYT")
        checkEqual(SolatCalendar.string(for: fajr, use24Hour: false), "6:01 AM", "12-hour form")
    }
    if let maghrib = first.time(for: .maghrib) {
        checkEqual(SolatCalendar.string(for: maghrib, use24Hour: true), "19:30", "maghrib renders as 19:30 MYT")
    }

    // Day bucketing must use the Malaysian boundary, not the system timezone.
    let dayStart = SolatCalendar.zoneCalendar.dateComponents(
        [.year, .month, .day], from: first.date
    )
    checkEqual(dayStart.day, 1, "day 1 buckets to 1 August in zone time")
    checkEqual(dayStart.month, 8, "month is August")

    // Events come back in chronological order.
    let order = first.events.map(\.prayer)
    checkEqual(order, [.imsak, .fajr, .syuruk, .dhuha, .dhuhr, .asr, .maghrib, .isha],
               "events are chronological")

    // Missing timestamps are dropped, not stored as epoch zero.
    let sparse = """
    {"zone":"SGR01","year":2026,"month":"AUG","month_number":8,
     "prayers":[{"day":3,"hijri":null,"fajr":1785708060,"maghrib":1785756540}]}
    """.data(using: .utf8)!
    if let sparseResponse = try? JSONDecoder().decode(MonthlyPrayerResponse.self, from: sparse) {
        let sparseDays = sparseResponse.toPrayerDays()
        checkEqual(sparseDays.first?.times.count, 2, "absent markers omitted")
        check(sparseDays.first?.time(for: .asr) == nil, "missing asr is nil")
    } else {
        check(false, "sparse payload decodes")
    }
}

// MARK: - Cache queries

func testCacheQueries() {
    section("PrayerCache queries")
    let cal = SolatCalendar.zoneCalendar

    func makeDay(offsetDays: Int, from base: Date) -> PrayerDay {
        let dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: offsetDays, to: base)!)
        var times: [String: Date] = [:]
        // Subuh 06:00, Zohor 13:20, Asar 16:30, Maghrib 19:25, Isyak 20:35.
        for (prayer, hour, minute) in [(Prayer.fajr, 6, 0), (.dhuhr, 13, 20),
                                        (.asr, 16, 30), (.maghrib, 19, 25), (.isha, 20, 35)] {
            times[prayer.rawValue] = cal.date(byAdding: DateComponents(hour: hour, minute: minute),
                                              to: dayStart)!
        }
        return PrayerDay(date: dayStart, hijri: "1448-01-01", times: times)
    }

    // Anchor at a fixed instant: 2026-08-17 15:00 MYT (between Zohor and Asar).
    var anchorComps = DateComponents()
    anchorComps.year = 2026; anchorComps.month = 8; anchorComps.day = 17
    anchorComps.hour = 15; anchorComps.minute = 0
    anchorComps.timeZone = SolatCalendar.zoneTimeZone
    let now = cal.date(from: anchorComps)!

    let days = (0..<32).map { makeDay(offsetDays: $0, from: now) }
    let cache = PrayerCache(zone: "SGR01", days: days, fetchedAt: now)

    checkEqual(cache.coverageDays(from: now), 32, "32 days of coverage counted")
    check(cache.day(containing: now) != nil, "today resolves")

    let upcoming = cache.upcomingEvents(from: now)
    checkEqual(upcoming.first?.prayer, .asr, "next prayer at 15:00 is Asar")
    check(upcoming.first!.date > now, "next event is in the future")

    // Ordering must hold across the day boundary.
    let firstFive = upcoming.prefix(5).map(\.prayer)
    checkEqual(Array(firstFive), [.asr, .maghrib, .isha, .fajr, .dhuhr],
               "rolls into tomorrow in order")

    // An empty cache must not claim coverage.
    let empty = PrayerCache.empty(zone: "SGR01")
    checkEqual(empty.coverageDays(from: now), 0, "empty cache has no coverage")
    check(empty.day(containing: now) == nil, "empty cache has no today")
    checkEqual(empty.upcomingEvents(from: now).count, 0, "empty cache has no events")

    // The 30-day promise.
    check(cache.coverageDays(from: now) >= PrayerStore.minimumCoverageDays,
          "cache satisfies the 30-day minimum")
}

// MARK: - Formatting

func testFormatting() {
    section("SolatCalendar formatting")
    checkEqual(SolatCalendar.formatHijri("1448-03-04"), "4 Rabiulawal 1448", "hijri month named")
    checkEqual(SolatCalendar.formatHijri("1448-02-17"), "17 Safar 1448", "Safar named")
    checkEqual(SolatCalendar.formatHijri("1448-12-01"), "1 Zulhijjah 1448", "Zulhijjah named")
    check(SolatCalendar.formatHijri(nil) == nil, "nil hijri stays nil")
    checkEqual(SolatCalendar.formatHijri("garbage"), "garbage", "unparseable string passes through")

    let base = Date(timeIntervalSince1970: 1_785_000_000)
    checkEqual(SolatCalendar.countdownString(until: base.addingTimeInterval(3600 * 2 + 720), from: base),
               "2h 12m", "hours and minutes")
    checkEqual(SolatCalendar.countdownString(until: base.addingTimeInterval(600), from: base),
               "10m", "minutes only")
    checkEqual(SolatCalendar.countdownString(until: base.addingTimeInterval(30), from: base),
               "<1m", "sub-minute")
    checkEqual(SolatCalendar.countdownString(until: base.addingTimeInterval(-60), from: base),
               "now", "past reads as now")
    checkEqual(SolatCalendar.preciseCountdownString(until: base.addingTimeInterval(3725), from: base),
               "1:02:05", "precise with hours")
    checkEqual(SolatCalendar.preciseCountdownString(until: base.addingTimeInterval(65), from: base),
               "1:05", "precise without hours")
}

// MARK: - Preferences

func testPreferences() {
    section("Preferences")
    // An isolated suite so the developer's real settings are untouched.
    let suiteName = "com.syahrul.mySolat.tests"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)

    let prefs = Preferences(defaults: defaults)
    checkEqual(prefs.zoneCode, "SGR01", "default zone is SGR01")
    checkEqual(prefs.preAlertMinutes, 15, "default pre-alert is 15 minutes")
    check(prefs.notifyAtPrayerTime, "on-time alerts default on")
    check(prefs.preAlertEnabled, "pre-alerts default on")
    checkEqual(prefs.enabledPrayers, Set(Prayer.allCases.filter(\.isObligatory)),
               "only the five obligatory prayers notify by default")
    checkEqual(prefs.visiblePrayers.count, 8, "all markers visible by default")

    // Clamping guards against a 0-minute pre-alert colliding with the on-time one.
    prefs.preAlertMinutes = 0
    checkEqual(prefs.preAlertMinutes, 1, "0 clamps up to 1")
    prefs.preAlertMinutes = 999
    checkEqual(prefs.preAlertMinutes, 120, "999 clamps down to 120")
    prefs.preAlertMinutes = 20
    checkEqual(prefs.preAlertMinutes, 20, "in-range value kept")

    prefs.showSecondaryMarkers = false
    checkEqual(prefs.visiblePrayers.count, 5, "hiding secondary markers leaves five")

    prefs.enabledPrayers = [.fajr, .maghrib]
    checkEqual(prefs.enabledPrayers, Set([Prayer.fajr, .maghrib]), "enabled set round-trips")

    prefs.menuBarStyle = .countdownOnly
    checkEqual(prefs.menuBarStyle, .countdownOnly, "menu bar style round-trips")

    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Cache serialisation

func testCacheRoundTrip() {
    section("Cache encode/decode")
    let cal = SolatCalendar.zoneCalendar
    let dayStart = cal.startOfDay(for: Date())
    let day = PrayerDay(date: dayStart, hijri: "1448-03-04",
                        times: [Prayer.fajr.rawValue: dayStart.addingTimeInterval(6 * 3600)])
    let cache = PrayerCache(zone: "PNG01", days: [day], fetchedAt: Date())

    guard let data = try? PrayerCacheFile.encoder().encode(cache),
          let decoded = try? PrayerCacheFile.decoder().decode(PrayerCache.self, from: data)
    else {
        check(false, "cache round-trips through JSON")
        return
    }
    check(true, "cache round-trips through JSON")
    checkEqual(decoded.zone, "PNG01", "zone survives")
    checkEqual(decoded.days.count, 1, "day count survives")
    checkEqual(decoded.days.first?.hijri, "1448-03-04", "hijri survives")
    check(abs(decoded.days.first!.time(for: .fajr)!.timeIntervalSince(day.time(for: .fajr)!)) < 1,
          "prayer instant survives to the second")
}

// MARK: - Zone catalog

func testZoneCatalog() {
    section("ZoneCatalog")
    let catalog = ZoneCatalog.shared
    // Bundled zones.json is absent when running the harness outside an .app, so
    // only assert behaviour that holds either way.
    if catalog.zones.isEmpty {
        print("  · no bundled catalog in the test harness — checking fallbacks only")
        checkEqual(catalog.describe(code: "SGR01"), "SGR01", "unknown code degrades to the raw code")
    } else {
        check(catalog.zones.count >= 50, "catalog has the full zone list (\(catalog.zones.count))")
        check(catalog.zone(for: "SGR01") != nil, "SGR01 resolves")
        check(catalog.zone(for: "sgr01") != nil, "lookup is case-insensitive")
        check(catalog.zone(for: "NOPE99") == nil, "bogus code does not resolve")
        check(catalog.describe(code: "SGR01").contains("Selangor"), "description names the state")
        check(!catalog.search("langkawi").isEmpty, "search finds Langkawi")
        check(!catalog.search("KTN").isEmpty, "search matches a code prefix")
        checkEqual(catalog.search("").count, catalog.zones.count, "empty query returns everything")
        check(catalog.groupedByNegeri.count >= 13, "zones grouped across the states")
    }
}

// MARK: - Widget data path

func testWidgetDataPath() {
    section("Widget shared-cache read path")
    // This is what PrayerTimelineProvider does first. It legitimately returns nil
    // when the app has never run, so a miss is reported rather than failed.
    if let cache = PrayerCacheFile.load() {
        check(true, "widget can read the shared cache")
        checkEqual(cache.zone.isEmpty, false, "cached zone is set (\(cache.zone))")
        let coverage = cache.coverageDays()
        print("     coverage: \(coverage) days, zone \(cache.zone)")
        check(coverage >= PrayerStore.minimumCoverageDays,
              "shared cache holds at least 30 days (\(coverage))")
        check(cache.day(containing: Date()) != nil, "today is present in the shared cache")
        check(cache.upcomingEvents(from: Date()).first != nil, "a next prayer is resolvable")
    } else {
        print("  · no shared cache on this machine yet — run the app once, then re-run tests")
    }
}

// MARK: - Live API smoke test

func testLiveAPI() async {
    section("Live API (set SOLAT_SKIP_NETWORK=1 to skip)")
    if ProcessInfo.processInfo.environment["SOLAT_SKIP_NETWORK"] == "1" {
        print("  · skipped")
        return
    }

    let api = WaktuSolatAPI(session: WaktuSolatAPI.makeDefaultSession())

    do {
        let zones = try await api.fetchZones()
        check(zones.count >= 50, "GET /zones returned \(zones.count) zones")
        check(zones.contains { $0.jakimCode == "SGR01" }, "SGR01 present in live zone list")
    } catch {
        check(false, "GET /zones failed: \(error)")
    }

    do {
        let comps = SolatCalendar.zoneCalendar.dateComponents([.year, .month], from: Date())
        let response = try await api.fetchMonth(zone: "SGR01", year: comps.year!, month: comps.month!)
        check(!response.prayers.isEmpty, "GET /v2/solat/SGR01 returned \(response.prayers.count) days")
        let days = response.toPrayerDays()
        check(days.count >= 28, "month flattens to \(days.count) usable days")
        check(days.allSatisfy { $0.time(for: .fajr) != nil }, "every day has a Subuh time")
        check(days.allSatisfy { day in
            guard let fajr = day.time(for: .fajr), let maghrib = day.time(for: .maghrib) else { return false }
            return fajr < maghrib
        }, "Subuh always precedes Maghrib")
    } catch {
        check(false, "GET /v2/solat/SGR01 failed: \(error)")
    }
}

// MARK: - Entry point

@main
struct TestRunner {
    static func main() async {
        print("mySolat test suite")
        print("──────────────────")

        testVersionComparison()
        testMonthsToCover()
        testResponseDecoding()
        testCacheQueries()
        testFormatting()
        testPreferences()
        testCacheRoundTrip()
        testZoneCatalog()
        testWidgetDataPath()
        await testLiveAPI()

        print("\n──────────────────")
        if failures.isEmpty {
            print("✓ all \(checks) checks passed")
            exit(0)
        } else {
            print("✗ \(failures.count) of \(checks) checks failed:")
            for failure in failures { print("   · \(failure)") }
            exit(1)
        }
    }
}
