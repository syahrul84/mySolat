import AppKit
import Combine
import Foundation
import SwiftUI
import WidgetKit

/// Single source of truth for the menu bar, popover, widget refresh and alerts.
@MainActor
final class AppState: ObservableObject {
    // MARK: Published UI state

    @Published private(set) var today: PrayerDay?
    @Published private(set) var nextEvent: PrayerEvent?
    @Published private(set) var currentEvent: PrayerEvent?
    @Published private(set) var coverageDays: Int = 0
    @Published private(set) var lastFetch: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notificationsAuthorized = false
    @Published private(set) var scheduledAlertCount = 0

    /// 1 Hz, for the popover's h:mm:ss countdown. Retained only while the popover
    /// is on screen.
    let clock = Ticker(interval: 1)

    /// Coarse clock for the menu bar. The menu bar countdown is minute-granular
    /// ("1h 12m"), so a second-by-second redraw was 15× more work than the text
    /// could ever reflect — and each redraw replicates across every display.
    /// Only runs for the two countdown styles; the others change when the prayer
    /// does, which `AppState` already publishes.
    let menuBarClock = Ticker(interval: 15)

    // MARK: Collaborators

    let prefs = Preferences()
    let updater = GitHubUpdater()
    let scheduler = NotificationScheduler()
    let alerts = AlertPresenter()
    /// Gates popups on the user actually being able to see them.
    let screen = ScreenActivityMonitor()
    private let api = WaktuSolatAPI(session: WaktuSolatAPI.makeDefaultSession())
    private var store: PrayerStore

    private var uiTimer: Timer?
    private var maintenanceTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastNotifiedEventID: String?

    /// Upcoming popup moments, rebuilt whenever the schedule or settings change.
    private var pendingAlerts: [PrayerAlert] = []
    private var firedAlertIDs: Set<String> = []
    /// Earliest un-fired alert. Lets the 1 Hz tick skip the whole scan with one
    /// date comparison instead of filtering the list every second.
    private var nextAlertFireDate: Date?

    init() {
        let preferences = Preferences()
        store = PrayerStore(zone: preferences.zoneCode)
    }

    // MARK: Lifecycle

    private var hasStarted = false

    /// Idempotent: SwiftUI may re-run the triggering `task` when the scene
    /// reappears, and we only want one set of timers.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        firedAlertIDs = Set(prefs.firedAlertIDs)

        // Unlocking or waking the display is the moment to reconsider anything
        // that came due while the user was away.
        screen.onBecameActive = { [weak self] in
            Task { @MainActor in self?.firePopupsIfDue(now: Date()) }
        }

        startTimers()
        observeWake()
        updateMenuBarClock()

        Task {
            await refreshFromCache()
            notificationsAuthorized = await scheduler.requestAuthorization()
            await ensureSchedule()
            await refresh(force: false)
            await ZoneCatalog.shared.refresh(api: api)
            updater.checkInBackgroundIfNeeded(prefs: prefs)
            prefs.hasCompletedSetup = true
        }
    }

    func stop() {
        if menuBarClock.isRunning { menuBarClock.release() }
        uiTimer?.invalidate()
        maintenanceTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func startTimers() {
        // 1s drives the countdown; cheap because it only touches published values.
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        uiTimer?.tolerance = 0.25

        // Hourly: roll the notification window forward and top up the cache.
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.performMaintenance() }
        }
        maintenanceTimer?.tolerance = 60
    }

    /// A sleeping Mac stops timers, so re-sync as soon as it wakes.
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.performMaintenance() }
        }
    }

    /// Runs at 1 Hz, so it must stay cheap.
    ///
    /// This publishes nothing on a normal tick — `Ticker` drives the countdown
    /// redraws. All this does is compare two dates, and only touch published state
    /// when the prayer we were counting down to has actually passed.
    private func onTick() {
        let now = Date()
        firePopupsIfDue(now: now)

        guard let next = nextEvent else {
            // No next event known (cold start, or cache just replaced).
            if !isResolvingNext { resolveCurrentAndNext(at: now) }
            return
        }

        guard next.date <= now else { return }

        // The prayer just entered: advance state, nudge the widget, and roll the
        // notification window so tomorrow stays covered.
        if lastNotifiedEventID != next.id {
            lastNotifiedEventID = next.id
            resolveCurrentAndNext(at: now, thenReschedule: true)
        }
    }

    /// Raises any popup whose moment has arrived.
    ///
    /// Called once a second, so the common path is a cheap scan of a short list.
    private func firePopupsIfDue(now: Date) {
        // Fast path: nothing is due, so don't touch the list at all.
        guard let earliest = nextAlertFireDate, now >= earliest else { return }

        // Locked, asleep, or screen-savering: hold everything untouched. Nothing is
        // shown and — crucially — nothing is marked as delivered, so it can still
        // surface when the user comes back. `onBecameActive` re-enters here.
        guard screen.isActive else { return }

        let window = prefs.catchUpWindow

        // Too late to be useful: retire silently rather than announce a prayer
        // that passed hours ago.
        let stale = PrayerAlertScheduler.expired(
            from: pendingAlerts, now: now, already: firedAlertIDs, window: window
        )
        if !stale.isEmpty { markFired(stale) }

        let due = PrayerAlertScheduler.due(
            from: pendingAlerts, now: now, already: firedAlertIDs, window: window
        )
        guard let alert = due.last else {   // latest is the truthful one
            recomputeNextAlertDate()
            return
        }
        markFired(due)   // never replay the rest of a backlog
        recomputeNextAlertDate()

        let wantsPopup = alert.kind == .atPrayerTime ? prefs.popupAtPrayerTime : prefs.popupBeforePrayer
        guard wantsPopup else { return }

        alerts.present(alert, zoneDescription: zoneDescription, prefs: prefs)
    }

    /// Caches the soonest alert still to fire.
    private func recomputeNextAlertDate() {
        nextAlertFireDate = pendingAlerts
            .filter { !firedAlertIDs.contains($0.id) }
            .map(\.fireDate)
            .min()
    }

    private func markFired(_ list: [PrayerAlert]) {
        for alert in list { firedAlertIDs.insert(alert.id) }
        // Persisted so a relaunch doesn't replay today's alerts.
        prefs.firedAlertIDs = Array(firedAlertIDs).sorted()
        firedAlertIDs = Set(prefs.firedAlertIDs)
    }

    /// Rebuilds the popup schedule from the cache and current settings.
    private func rebuildAlerts() async {
        let lookback = max(prefs.catchUpWindow, PrayerAlertScheduler.defaultCatchUpWindow)
        let events = await store.upcomingEvents(from: Date().addingTimeInterval(-lookback), limit: 12)
        pendingAlerts = PrayerAlertScheduler.alerts(for: events, prefs: prefs)
        recomputeNextAlertDate()
    }

    /// Shows a sample popup so the user can see and hear what they've configured.
    func previewAlert(kind: PrayerAlertKind) {
        let event = nextEvent ?? PrayerEvent(prayer: .maghrib, date: Date().addingTimeInterval(900))
        let alert = PrayerAlert(
            prayer: event.prayer,
            prayerDate: event.date,
            fireDate: kind == .atPrayerTime ? event.date : event.date.addingTimeInterval(-Double(prefs.preAlertMinutes) * 60),
            kind: kind,
            minutesBefore: prefs.preAlertMinutes
        )
        alerts.present(alert, zoneDescription: zoneDescription, prefs: prefs)
    }

    private var isResolvingNext = false

    private func resolveCurrentAndNext(at now: Date, thenReschedule: Bool = false) {
        isResolvingNext = true
        Task {
            let next = await store.nextEvent(from: now)
            let current = await store.currentEvent(now: now)
            nextEvent = next
            currentEvent = current
            isResolvingNext = false

            // Day boundary crossed — today's rows need replacing.
            if let today, !SolatCalendar.zoneCalendar.isDate(today.date, inSameDayAs: now) {
                await refreshFromCache()
            }

            if thenReschedule {
                reloadWidget()
                await ensureSchedule()
            }
        }
    }

    private func performMaintenance() async {
        screen.recomputeActive()
        await refresh(force: false)
        await ensureSchedule()
        reloadWidget()
        updater.checkInBackgroundIfNeeded(prefs: prefs)
    }

    // MARK: Data

    private func refreshFromCache() async {
        let cache = await store.currentCache
        today = await store.today()
        nextEvent = await store.nextEvent(from: Date())
        currentEvent = await store.currentEvent(now: Date())
        coverageDays = cache.coverageDays()
        lastFetch = cache.fetchedAt == .distantPast ? nil : cache.fetchedAt
    }

    /// Tops up the 30-day cache. `force` bypasses the coverage check.
    func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await store.refresh(force: force)
            errorMessage = nil
        } catch {
            // Keep showing cached times; only surface the error if we have nothing.
            let coverage = await store.coverageDays
            errorMessage = coverage > 0
                ? nil
                : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        await refreshFromCache()
        await ensureSchedule()
        reloadWidget()
    }

    /// Recomputes the rolling notification window from the current cache.
    func ensureSchedule() async {
        await scheduler.refreshAuthorizationStatus()
        notificationsAuthorized = scheduler.isAuthorized

        let events = await store.upcomingEvents(from: Date(), limit: 120)
        await scheduler.reschedule(
            events: events,
            prefs: prefs,
            zoneDescription: ZoneCatalog.shared.describe(code: prefs.zoneCode)
        )
        scheduledAlertCount = scheduler.lastScheduledCount
        await rebuildAlerts()
    }

    // MARK: Actions

    func changeZone(to code: String) async {
        prefs.zoneCode = code
        await store.setZone(code)
        await refreshFromCache()
        await refresh(force: true)
    }

    /// Detects the user's zone from GPS and switches to it.
    func detectZone(using resolver: LocationResolver) async throws {
        let location = try await resolver.currentLocation()
        let code = try await api.detectZone(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        await changeZone(to: code)
    }

    /// Starts or stops the menu bar clock to match the current display style.
    private func updateMenuBarClock() {
        let needsTicking: Bool
        switch prefs.menuBarStyle {
        case .nameAndCountdown, .countdownOnly: needsTicking = true
        case .nameAndTime, .timeOnly, .iconOnly: needsTicking = false
        }
        if needsTicking, !menuBarClock.isRunning {
            menuBarClock.retain()
        } else if !needsTicking, menuBarClock.isRunning {
            menuBarClock.release()
        }
    }

    /// Called after any notification-related setting changes.
    func settingsChanged() async {
        updateMenuBarClock()
        await ensureSchedule()
        reloadWidget()
        objectWillChange.send()
    }

    func sendTestNotification() async {
        notificationsAuthorized = await scheduler.requestAuthorization()
        await scheduler.sendTestNotification(prefs: prefs)
    }

    func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    func openTipPage() { NSWorkspace.shared.open(AppIdentifiers.tipURL) }
    func openRepo() { NSWorkspace.shared.open(AppIdentifiers.repoURL) }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppIdentifiers.widgetKind)
    }

    // MARK: Derived display values

    var zoneDescription: String { ZoneCatalog.shared.describe(code: prefs.zoneCode) }

    var hijriDescription: String? { SolatCalendar.formatHijri(today?.hijri) }

    /// Prayer rows for the popover, honouring the secondary-marker preference.
    var visibleEvents: [PrayerEvent] {
        guard let today else { return [] }
        let visible = Set(prefs.visiblePrayers)
        return today.events.filter { visible.contains($0.prayer) }
    }

    /// The text drawn in the menu bar at a given instant.
    func menuBarTitle(now: Date = Date()) -> String {
        guard let nextEvent else { return coverageDays == 0 ? "—" : "…" }
        let time = SolatCalendar.string(for: nextEvent.date, use24Hour: prefs.use24HourClock)
        let countdown = SolatCalendar.countdownString(until: nextEvent.date, from: now)

        switch prefs.menuBarStyle {
        case .nameAndTime: return "\(nextEvent.prayer.displayName) \(time)"
        case .nameAndCountdown: return "\(nextEvent.prayer.displayName) \(countdown)"
        case .timeOnly: return time
        case .countdownOnly: return countdown
        case .iconOnly: return ""
        }
    }

    var menuBarSymbol: String { nextEvent?.prayer.symbolName ?? "moon.stars" }

    /// Whether the cache still meets the 30-day promise, for the settings badge.
    var coverageIsHealthy: Bool { coverageDays >= PrayerStore.minimumCoverageDays }
}
