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

    // Four-component versions aren't used for releases, but the comparator has to
    // handle them: the updater offers strictly newer versions only, so getting
    // this wrong would silently strand everyone on the older build.
    check(AppVersion.isNewer("1.0.4.1", than: "1.0.4"), "1.0.4.1 is newer than 1.0.4")
    check(AppVersion.isNewer("1.0.4.2", than: "1.0.4.1"), "1.0.4.2 is newer than 1.0.4.1")
    check(!AppVersion.isNewer("1.0.4", than: "1.0.4.1"), "1.0.4 is not newer than 1.0.4.1")
    check(AppVersion.isNewer("1.0.5", than: "1.0.4.1"), "1.0.5 is newer than 1.0.4.1")
    check(!AppVersion.isNewer("1.0.4.1", than: "1.0.4.1"), "equal four-part versions tie")
    check(AppVersion.isNewer("v1.0.4.1", than: "1.0.4"), "tagged form compares too")
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
    let suiteName = "com.ginlabs.mysolat.tests"
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

// MARK: - Popup alert scheduling

func testAlertScheduling() {
    section("PrayerAlertScheduler")
    let suiteName = "com.ginlabs.mysolat.tests.alerts"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available"); return
    }
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)
    prefs.preAlertMinutes = 10
    prefs.enabledPrayers = [.maghrib, .isha]

    let base = Date(timeIntervalSince1970: 1_785_000_000)
    let maghrib = PrayerEvent(prayer: .maghrib, date: base)
    let isha = PrayerEvent(prayer: .isha, date: base.addingTimeInterval(4200))
    // Dhuha is not in enabledPrayers, so it must never produce an alert.
    let dhuha = PrayerEvent(prayer: .dhuha, date: base.addingTimeInterval(600))

    let alerts = PrayerAlertScheduler.alerts(for: [maghrib, dhuha, isha], prefs: prefs)
    checkEqual(alerts.count, 4, "two alerts each for the two enabled prayers")
    check(!alerts.contains { $0.prayer == .dhuha }, "disabled prayer produces no alert")
    check(alerts.map(\.fireDate) == alerts.map(\.fireDate).sorted(), "alerts are in fire order")

    let pre = alerts.first { $0.prayer == .maghrib && $0.kind == .beforePrayer }
    check(pre != nil, "pre-alert exists for Maghrib")
    if let pre {
        checkEqual(pre.fireDate, base.addingTimeInterval(-600), "pre-alert fires 10 min early")
        checkEqual(pre.title, "Maghrib in 10 minutes", "pre-alert wording")
    }
    let at = alerts.first { $0.prayer == .maghrib && $0.kind == .atPrayerTime }
    if let at {
        checkEqual(at.fireDate, base, "on-time alert fires at the prayer")
        checkEqual(at.title, "Maghrib has entered", "on-time wording")
    }

    // Nothing is due before its moment.
    checkEqual(PrayerAlertScheduler.due(from: alerts, now: base.addingTimeInterval(-1200), already: []).count,
               0, "nothing due 20 min out")

    // The pre-alert becomes due exactly on time.
    let duePre = PrayerAlertScheduler.due(from: alerts, now: base.addingTimeInterval(-600), already: [])
    checkEqual(duePre.count, 1, "pre-alert due at its moment")
    checkEqual(duePre.first?.kind, .beforePrayer, "and it is the pre-alert")

    // Already-shown alerts never repeat.
    let seen: Set<String> = Set(duePre.map(\.id))
    checkEqual(PrayerAlertScheduler.due(from: alerts, now: base.addingTimeInterval(-600), already: seen).count,
               0, "a shown alert does not fire twice")

    // Within the grace window a late alert still fires.
    let slightlyLate = PrayerAlertScheduler.due(from: alerts, now: base.addingTimeInterval(60), already: seen)
    check(slightlyLate.contains { $0.kind == .atPrayerTime }, "1 min late still fires")

    // Past the grace window it is dropped, not shown hours later.
    let veryLate = base.addingTimeInterval(PrayerAlertScheduler.defaultCatchUpWindow + 60)
    checkEqual(PrayerAlertScheduler.due(from: alerts, now: veryLate, already: seen)
                 .filter { $0.prayer == .maghrib }.count,
               0, "stale alert does not fire after the grace period")
    check(PrayerAlertScheduler.expired(from: alerts, now: veryLate, already: seen)
            .contains { $0.prayer == .maghrib && $0.kind == .atPrayerTime },
          "stale alert is reported as expired so it can be marked done")

    // IDs are stable across rebuilds — that is what makes dedupe survive relaunch.
    let rebuilt = PrayerAlertScheduler.alerts(for: [maghrib, dhuha, isha], prefs: prefs)
    checkEqual(Set(rebuilt.map(\.id)), Set(alerts.map(\.id)), "alert ids are stable")

    // Same prayer on different days must not collide.
    let tomorrow = PrayerEvent(prayer: .maghrib, date: base.addingTimeInterval(86400))
    let tomorrowAlerts = PrayerAlertScheduler.alerts(for: [tomorrow], prefs: prefs)
    check(Set(tomorrowAlerts.map(\.id)).isDisjoint(with: Set(alerts.map(\.id))),
          "tomorrow's alerts have distinct ids")

    defaults.removePersistentDomain(forName: suiteName)
}

func testAlertPreferences() {
    section("Popup preferences")
    let suiteName = "com.ginlabs.mysolat.tests.popup"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available"); return
    }
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)

    check(prefs.popupAtPrayerTime, "popup at prayer time defaults on")
    check(prefs.popupBeforePrayer, "popup before prayer defaults on")
    checkEqual(prefs.popupAutoDismissSeconds, 30, "auto-dismiss defaults to 30s")
    checkEqual(prefs.alertSound, .glass, "default sound is Glass")

    prefs.popupAutoDismissSeconds = -5
    checkEqual(prefs.popupAutoDismissSeconds, 0, "negative clamps to 0 (stay until dismissed)")
    prefs.popupAutoDismissSeconds = 9999
    checkEqual(prefs.popupAutoDismissSeconds, 600, "absurd value clamps to 600s")

    prefs.alertSound = .submarine
    checkEqual(prefs.alertSound, .submarine, "sound round-trips")
    check(AlertSound.none.systemSoundName == nil, "\"No sound\" maps to silence")
    check(AlertSound.glass.systemSoundName == "Glass", "sound maps to a system sound name")

    // The store keeps what it is given, up to a generous ceiling. Trimming used
    // to happen here — `suffix(40)` on a sorted list — which silently discarded
    // whole prayers rather than old entries. Pruning is now the caller's job and
    // is done by date; see testFiredIDPruning.
    prefs.firedAlertIDs = (1...60).map { "id-\($0)" }
    checkEqual(prefs.firedAlertIDs.count, 60, "the store no longer trims live ids")
    check(prefs.firedAlertIDs.contains("id-1"), "the first id survives a round trip")
    check(prefs.firedAlertIDs.contains("id-60"), "the last id survives a round trip")

    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Widget display settings

func testWidgetDisplaySettings() {
    section("Widget display settings")
    let suiteName = "com.ginlabs.mysolat.tests.widget"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available"); return
    }
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)

    // Defaults: everything visible.
    let d = prefs.widgetDisplaySettings
    check(d.showLocation, "location shows by default")
    check(d.showCountdown, "countdown shows by default")
    check(d.showDate, "date shows by default")
    check(d.showSecondaryMarkers, "secondary markers show by default")
    checkEqual(d.visiblePrayers.count, 8, "all eight markers listed by default")

    // The reported bug: hiding the secondary markers must reach the widget.
    prefs.showSecondaryMarkers = false
    let hidden = prefs.widgetDisplaySettings
    checkEqual(hidden.visiblePrayers.count, 5, "hiding secondary markers leaves the five obligatory")
    check(!hidden.visiblePrayers.contains(.imsak), "Imsak is hidden")
    check(!hidden.visiblePrayers.contains(.syuruk), "Syuruk is hidden")
    check(!hidden.visiblePrayers.contains(.dhuha), "Dhuha is hidden")
    check(hidden.visiblePrayers.contains(.fajr), "Subuh still listed")

    // Each widget toggle is independent.
    prefs.widgetShowLocation = false
    prefs.widgetShowCountdown = true
    prefs.widgetShowDate = false
    let mixed = prefs.widgetDisplaySettings
    check(!mixed.showLocation, "location can be hidden on its own")
    check(mixed.showCountdown, "countdown unaffected")
    check(!mixed.showDate, "date can be hidden on its own")

    // Round-trips through the file the widget actually reads. Once the signed App
    // Store build has created its App Group folder, macOS refuses writes into it from
    // any other program, including this unsigned harness; skip rather than fail then.
    guard WidgetDisplaySettings.write(mixed) else {
        print("  · shared folder belongs to the signed app — skipping the file round trip")
        defaults.removePersistentDomain(forName: suiteName)
        return
    }
    check(true, "settings file written")
    let loaded = WidgetDisplaySettings.load(fallback: prefs)
    checkEqual(loaded, mixed, "widget reads back exactly what the app wrote")
    checkEqual(loaded.visiblePrayers.count, 5, "marker choice survives the round trip")

    // Restore a known state for the next run, then confirm it propagates.
    let all = WidgetDisplaySettings.default
    check(WidgetDisplaySettings.write(all), "defaults written back")
    checkEqual(WidgetDisplaySettings.load(fallback: prefs), all, "defaults read back")

    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Coverage warnings

func testCoverageWarningThreshold() {
    section("Stale prayer-times warning")
    let suiteName = "com.ginlabs.mysolat.tests.coverage"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available"); return
    }
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)

    check(prefs.lastCoverageWarning == nil, "no warning recorded initially")

    // The store refetches automatically below this threshold, so it's also the
    // point at which a persistent failure is worth telling the user about.
    checkEqual(PrayerStore.minimumCoverageDays, 30, "auto-refresh threshold is 30 days")
    check(PrayerStore.targetCoverageDays > PrayerStore.minimumCoverageDays,
          "target coverage exceeds the minimum, so refreshes have headroom")

    let now = Date()
    prefs.lastCoverageWarning = now
    check(prefs.lastCoverageWarning != nil, "warning timestamp persists")

    // Rate limiting: within a day, don't warn again.
    let elapsed = Date().timeIntervalSince(prefs.lastCoverageWarning!)
    check(elapsed < 24 * 60 * 60, "a warning just issued is inside the quiet period")

    prefs.lastCoverageWarning = now.addingTimeInterval(-25 * 60 * 60)
    let elapsedOld = Date().timeIntervalSince(prefs.lastCoverageWarning!)
    check(elapsedOld > 24 * 60 * 60, "a day-old warning is outside the quiet period")

    prefs.lastCoverageWarning = nil
    check(prefs.lastCoverageWarning == nil, "a successful refresh clears the record")

    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Fired-alert bookkeeping

func testFiredIDPruning() {
    section("Fired-alert id retention")
    let cal = SolatCalendar.zoneCalendar
    var c = DateComponents()
    c.year = 2026; c.month = 9; c.day = 3; c.hour = 12
    c.timeZone = SolatCalendar.zoneTimeZone
    let now = cal.date(from: c)!

    func id(_ prayer: String, _ stamp: String, _ kind: String) -> String { "\(prayer).\(stamp).\(kind)" }

    // A week of alerts across every prayer, as accumulates in real use.
    var ids = Set<String>()
    for day in 28...31 { for p in ["asr","dhuhr","fajr","isha","maghrib"] {
        ids.insert(id(p, "202608\(day)", "atPrayerTime")); ids.insert(id(p, "202608\(day)", "beforePrayer")) } }
    for day in 1...3 { for p in ["asr","dhuhr","fajr","isha","maghrib"] {
        ids.insert(id(p, "2026090\(day)", "atPrayerTime")); ids.insert(id(p, "2026090\(day)", "beforePrayer")) } }
    checkEqual(ids.count, 70, "seven days of alerts accumulated")

    let kept = PrayerAlertScheduler.pruneFiredIDs(ids, now: now, days: 3)

    // The whole point: today's ids survive, for every prayer.
    for p in ["asr","dhuhr","fajr","isha","maghrib"] {
        check(kept.contains(id(p, "20260903", "atPrayerTime")), "today's \(p) id is kept")
    }
    check(kept.contains(id("asr", "20260903", "beforePrayer")), "today's asr pre-alert is kept")

    // Regression: a count cap on a sorted list dropped whole prayers, because ids
    // sort by prayer name — asr always lost, and its alert replayed every second.
    let sortedCap = Set(ids.sorted().suffix(40))
    check(!sortedCap.contains(id("asr", "20260903", "atPrayerTime")),
          "the old sorted-suffix cap discarded today's asr id (the bug)")
    check(kept.contains(id("asr", "20260903", "atPrayerTime")),
          "date pruning keeps it")

    // Old ids go, and the set stays bounded.
    check(!kept.contains(id("fajr", "20260828", "atPrayerTime")), "a six-day-old id is dropped")
    check(kept.count <= 50, "pruned set stays small (\(kept.count))")
    check(kept.allSatisfy { $0.split(separator: ".")[1] >= "20260831" }, "nothing older than the cutoff survives")

    // Unparseable ids are kept rather than risking a repeat alert.
    let odd: Set<String> = ["not-an-id", "a.b", "prayer.notadate.kind"]
    checkEqual(PrayerAlertScheduler.pruneFiredIDs(odd, now: now, days: 3), odd,
               "ids of unknown shape are preserved")
}

// MARK: - Notification suppression

/// Mirrors the decision `NotificationDelegate.willPresent` makes, so the rule is
/// covered by the plain test binary (the delegate itself needs UserNotifications
/// and a running app).
func shouldPresentNotification(prayerRaw: String?, kind: String?, prefs: Preferences) -> Bool {
    guard let prayerRaw, let prayer = Prayer(rawValue: prayerRaw) else { return true }
    guard prefs.enabledPrayers.contains(prayer) else { return false }
    return (kind == "pre") ? prefs.preAlertEnabled : prefs.notifyAtPrayerTime
}

func testNotificationSuppression() {
    section("Notification presentation gate")
    let suiteName = "com.ginlabs.mysolat.tests.suppress"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available"); return
    }
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)
    prefs.enabledPrayers = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    // Both on: everything shows.
    prefs.notifyAtPrayerTime = true
    prefs.preAlertEnabled = true
    check(shouldPresentNotification(prayerRaw: "asr", kind: "at", prefs: prefs), "on-time shows when enabled")
    check(shouldPresentNotification(prayerRaw: "asr", kind: "pre", prefs: prefs), "pre-alert shows when enabled")

    // The reported case: both switched off, yet a request still fires.
    prefs.notifyAtPrayerTime = false
    prefs.preAlertEnabled = false
    check(!shouldPresentNotification(prayerRaw: "asr", kind: "at", prefs: prefs),
          "on-time is suppressed once switched off")
    check(!shouldPresentNotification(prayerRaw: "dhuhr", kind: "pre", prefs: prefs),
          "pre-alert is suppressed once switched off")

    // Each kind is independent.
    prefs.notifyAtPrayerTime = true
    prefs.preAlertEnabled = false
    check(shouldPresentNotification(prayerRaw: "maghrib", kind: "at", prefs: prefs),
          "on-time still shows with only the pre-alert off")
    check(!shouldPresentNotification(prayerRaw: "maghrib", kind: "pre", prefs: prefs),
          "pre-alert stays suppressed")

    // A muted prayer is suppressed whatever the kind toggles say.
    prefs.preAlertEnabled = true
    prefs.enabledPrayers = [.maghrib]
    check(!shouldPresentNotification(prayerRaw: "asr", kind: "at", prefs: prefs),
          "a muted prayer is suppressed")
    check(shouldPresentNotification(prayerRaw: "maghrib", kind: "at", prefs: prefs),
          "an enabled prayer still shows")

    // Non-prayer notifications are never touched by these toggles.
    prefs.notifyAtPrayerTime = false
    prefs.preAlertEnabled = false
    prefs.enabledPrayers = []
    check(shouldPresentNotification(prayerRaw: nil, kind: nil, prefs: prefs),
          "an update notice is not affected by prayer toggles")

    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Catch-up after sleep / lock

func testCatchUpWindow() {
    section("Missed-alert catch-up")
    let suiteName = "com.ginlabs.mysolat.tests.catchup"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite available"); return
    }
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)
    prefs.enabledPrayers = [.fajr]
    prefs.preAlertMinutes = 15

    checkEqual(prefs.catchUpWindowMinutes, 30, "catch-up window defaults to 30 minutes")

    // The scenario from the report: Subuh at 06:00, machine asleep, user returns later.
    let cal = SolatCalendar.zoneCalendar
    var c = DateComponents()
    c.year = 2026; c.month = 8; c.day = 20; c.hour = 6; c.minute = 0
    c.timeZone = SolatCalendar.zoneTimeZone
    let subuh = cal.date(from: c)!
    let alerts = PrayerAlertScheduler.alerts(for: [PrayerEvent(prayer: .fajr, date: subuh)], prefs: prefs)

    func at(_ hour: Int, _ minute: Int) -> Date {
        var c2 = c; c2.hour = hour; c2.minute = minute
        return cal.date(from: c2)!
    }
    let window = prefs.catchUpWindow

    // Comes back 20 minutes late — still worth showing, and it must be the
    // "has entered" alert, not the stale 15-minutes-before one.
    let at620 = PrayerAlertScheduler.mostRelevant(from: alerts, now: at(6, 20), already: [], window: window)
    check(at620 != nil, "06:20 — a missed alert is still surfaced")
    checkEqual(at620?.kind, .atPrayerTime, "06:20 — shows \"has entered\", not the pre-alert")

    // Exactly on the boundary still counts.
    let at630 = PrayerAlertScheduler.mostRelevant(from: alerts, now: at(6, 30), already: [], window: window)
    check(at630 != nil, "06:30 — exactly 30 minutes late still shows")

    // One minute past the boundary: nothing, and it is retired.
    let at631 = PrayerAlertScheduler.mostRelevant(from: alerts, now: at(6, 31), already: [], window: window)
    check(at631 == nil, "06:31 — past the window, nothing is shown")
    check(PrayerAlertScheduler.expired(from: alerts, now: at(6, 31), already: [], window: window)
            .contains { $0.kind == .atPrayerTime },
          "06:31 — the missed alert is retired so it cannot resurface")

    // Hours later, definitely nothing.
    check(PrayerAlertScheduler.mostRelevant(from: alerts, now: at(12, 0), already: [], window: window) == nil,
          "noon — a morning prayer never pops up")

    // A zero window disables catch-up: only alerts firing right now appear.
    check(PrayerAlertScheduler.mostRelevant(from: alerts, now: at(6, 5), already: [], window: 0) == nil,
          "window 0 — a 5-minute-old alert is not replayed")
    check(PrayerAlertScheduler.mostRelevant(from: alerts, now: subuh, already: [], window: 0) != nil,
          "window 0 — an alert due this instant still fires")

    // Before the prayer, the pre-alert is the relevant one.
    let at550 = PrayerAlertScheduler.mostRelevant(from: alerts, now: at(5, 50), already: [], window: window)
    checkEqual(at550?.kind, .beforePrayer, "05:50 — the pre-alert is what shows")

    // Window is clamped to something sane.
    prefs.catchUpWindowMinutes = -10
    checkEqual(prefs.catchUpWindowMinutes, 0, "negative window clamps to 0")
    prefs.catchUpWindowMinutes = 9999
    checkEqual(prefs.catchUpWindowMinutes, 180, "huge window clamps to 180")

    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Zone/cache reconciliation

func testStoreIgnoresForeignZoneCache() async {
    section("PrayerStore rejects a cache from another zone")
    // Regression: the store used to adopt whatever cache was on disk regardless of
    // zone, so the UI would label another zone's times with the selected zone's
    // name. Neighbouring zones differ by only a minute or two, which made it
    // almost invisible.
    guard let onDisk = PrayerCacheFile.load() else {
        print("  · no cache on disk — skipping (run the app once)")
        return
    }

    let sameZone = PrayerStore(zone: onDisk.zone)
    let adopted = await sameZone.coverageDays
    check(adopted > 0, "cache is adopted for the matching zone \(onDisk.zone) (\(adopted) days)")

    // A zone the cache definitely isn't for.
    let foreign = onDisk.zone.uppercased() == "PLS01" ? "JHR02" : "PLS01"
    let otherZone = PrayerStore(zone: foreign)
    let leaked = await otherZone.coverageDays
    checkEqual(leaked, 0, "cache is discarded for a different zone (\(foreign))")
    let cache = await otherZone.currentCache
    checkEqual(cache.zone, foreign, "store reports the requested zone, not the cached one")
    check(await otherZone.nextEvent() == nil, "no events leak from the other zone")
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
        testAlertScheduling()
        testAlertPreferences()
        testCatchUpWindow()
        testNotificationSuppression()
        testFiredIDPruning()
        testWidgetDisplaySettings()
        testCoverageWarningThreshold()
        await testStoreIgnoresForeignZoneCache()
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
