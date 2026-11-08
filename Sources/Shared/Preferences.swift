import Foundation

/// How the menu bar item renders itself.
enum MenuBarStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case nameAndTime      // "Asar 4:32 PM"
    case nameAndCountdown // "Asar in 1h 12m"
    case timeOnly         // "4:32 PM"
    case countdownOnly    // "1h 12m"
    case iconOnly         // just the glyph

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nameAndTime: return "Prayer name + time"
        case .nameAndCountdown: return "Prayer name + countdown"
        case .timeOnly: return "Time only"
        case .countdownOnly: return "Countdown only"
        case .iconOnly: return "Icon only"
        }
    }
}

/// User settings, stored in the App Group defaults so the widget sees them too.
///
/// This is a thin typed wrapper rather than `@AppStorage` because the widget
/// extension needs to read the same values without a SwiftUI environment.
enum PreferenceKeys {
    static let zoneCode = "zoneCode"
    static let use24HourClock = "use24HourClock"
    static let menuBarStyle = "menuBarStyle"
    static let showSecondaryMarkers = "showSecondaryMarkers"
    static let widgetShowLocation = "widgetShowLocation"
    static let widgetShowCountdown = "widgetShowCountdown"
    static let widgetShowDate = "widgetShowDate"
    static let lastCoverageWarning = "lastCoverageWarning"
    static let notifyAtPrayerTime = "notifyAtPrayerTime"
    static let preAlertMinutes = "preAlertMinutes"
    static let preAlertEnabled = "preAlertEnabled"
    static let enabledPrayers = "enabledPrayers"
    static let notificationSoundEnabled = "notificationSoundEnabled"
    static let alertSoundName = "alertSoundName"
    static let popupAtPrayerTime = "popupAtPrayerTime"
    static let popupBeforePrayer = "popupBeforePrayer"
    static let popupAutoDismissSeconds = "popupAutoDismissSeconds"
    static let catchUpWindowMinutes = "catchUpWindowMinutes"
    static let firedAlertIDs = "firedAlertIDs"
    static let launchAtLogin = "launchAtLogin"
    static let hasCompletedSetup = "hasCompletedSetup"
}

struct Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKeys.zoneCode: "SGR01",
            PreferenceKeys.use24HourClock: false,
            PreferenceKeys.menuBarStyle: MenuBarStyle.nameAndTime.rawValue,
            PreferenceKeys.showSecondaryMarkers: true,
            PreferenceKeys.widgetShowLocation: true,
            PreferenceKeys.widgetShowCountdown: true,
            PreferenceKeys.widgetShowDate: true,
            PreferenceKeys.notifyAtPrayerTime: true,
            PreferenceKeys.preAlertEnabled: true,
            PreferenceKeys.preAlertMinutes: 15,
            PreferenceKeys.notificationSoundEnabled: true,
            PreferenceKeys.alertSoundName: AlertSound.glass.rawValue,
            PreferenceKeys.popupAtPrayerTime: true,
            PreferenceKeys.popupBeforePrayer: true,
            PreferenceKeys.popupAutoDismissSeconds: 30,
            PreferenceKeys.catchUpWindowMinutes: 30,
            PreferenceKeys.enabledPrayers: Prayer.allCases.filter(\.isObligatory).map(\.rawValue),
            PreferenceKeys.launchAtLogin: false,
            PreferenceKeys.hasCompletedSetup: false,
        ])
    }

    // MARK: Location

    var zoneCode: String {
        get { defaults.string(forKey: PreferenceKeys.zoneCode) ?? "SGR01" }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.zoneCode) }
    }

    // MARK: Display

    var use24HourClock: Bool {
        get { defaults.bool(forKey: PreferenceKeys.use24HourClock) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.use24HourClock) }
    }

    var menuBarStyle: MenuBarStyle {
        get {
            let raw = defaults.string(forKey: PreferenceKeys.menuBarStyle) ?? ""
            return MenuBarStyle(rawValue: raw) ?? .nameAndTime
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.menuBarStyle) }
    }

    /// Whether Imsak/Syuruk/Dhuha appear in the popover and widget.
    var showSecondaryMarkers: Bool {
        get { defaults.bool(forKey: PreferenceKeys.showSecondaryMarkers) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.showSecondaryMarkers) }
    }

    // MARK: Notifications

    /// Notify exactly when the prayer time enters.
    var notifyAtPrayerTime: Bool {
        get { defaults.bool(forKey: PreferenceKeys.notifyAtPrayerTime) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.notifyAtPrayerTime) }
    }

    /// Notify N minutes early so the user can prepare.
    var preAlertEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKeys.preAlertEnabled) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.preAlertEnabled) }
    }

    /// Clamped to 1...120 minutes; 0 would collide with the on-time alert.
    var preAlertMinutes: Int {
        get { min(120, max(1, defaults.integer(forKey: PreferenceKeys.preAlertMinutes))) }
        nonmutating set { defaults.set(min(120, max(1, newValue)), forKey: PreferenceKeys.preAlertMinutes) }
    }

    var notificationSoundEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKeys.notificationSoundEnabled) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.notificationSoundEnabled) }
    }

    /// Sound played with the on-screen popup.
    var alertSound: AlertSound {
        get {
            let raw = defaults.string(forKey: PreferenceKeys.alertSoundName) ?? ""
            return AlertSound(rawValue: raw) ?? .glass
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.alertSoundName) }
    }

    // MARK: On-screen popup
    //
    // Notification banners auto-hide after a few seconds, which is easy to miss.
    // The popup is a floating panel that stays until dismissed (or until the
    // auto-dismiss timer runs out) and shows above other apps.

    var popupAtPrayerTime: Bool {
        get { defaults.bool(forKey: PreferenceKeys.popupAtPrayerTime) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.popupAtPrayerTime) }
    }

    var popupBeforePrayer: Bool {
        get { defaults.bool(forKey: PreferenceKeys.popupBeforePrayer) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.popupBeforePrayer) }
    }

    /// Seconds before the popup closes itself. 0 means it stays until dismissed.
    var popupAutoDismissSeconds: Int {
        get {
            let value = defaults.integer(forKey: PreferenceKeys.popupAutoDismissSeconds)
            return min(600, max(0, value))
        }
        nonmutating set {
            defaults.set(min(600, max(0, newValue)), forKey: PreferenceKeys.popupAutoDismissSeconds)
        }
    }

    /// How many minutes late a missed alert may still be shown once the screen
    /// becomes active again. 0 disables catch-up entirely.
    var catchUpWindowMinutes: Int {
        get { min(180, max(0, defaults.integer(forKey: PreferenceKeys.catchUpWindowMinutes))) }
        nonmutating set {
            defaults.set(min(180, max(0, newValue)), forKey: PreferenceKeys.catchUpWindowMinutes)
        }
    }

    var catchUpWindow: TimeInterval { TimeInterval(catchUpWindowMinutes) * 60 }

    /// Alerts already shown, so a relaunch doesn't replay them.
    ///
    /// Callers prune this by day before storing. There is deliberately no count
    /// cap here: the previous `suffix(40)` trimmed a *sorted* list, and because
    /// ids sort by prayer name it removed every `asr` entry rather than the
    /// oldest ones. The generous ceiling below only guards runaway growth.
    var firedAlertIDs: [String] {
        get { defaults.stringArray(forKey: PreferenceKeys.firedAlertIDs) ?? [] }
        nonmutating set { defaults.set(Array(newValue.suffix(500)), forKey: PreferenceKeys.firedAlertIDs) }
    }

    var enabledPrayers: Set<Prayer> {
        get {
            let raw = defaults.stringArray(forKey: PreferenceKeys.enabledPrayers) ?? []
            return Set(raw.compactMap(Prayer.init(rawValue:)))
        }
        nonmutating set {
            let ordered = Prayer.displayOrder.filter(newValue.contains).map(\.rawValue)
            defaults.set(ordered, forKey: PreferenceKeys.enabledPrayers)
        }
    }

    // MARK: System

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: PreferenceKeys.launchAtLogin) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.launchAtLogin) }
    }

    var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: PreferenceKeys.hasCompletedSetup) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.hasCompletedSetup) }
    }

    /// Markers the UI should list, honouring `showSecondaryMarkers`.
    var visiblePrayers: [Prayer] {
        showSecondaryMarkers ? Prayer.displayOrder : Prayer.displayOrder.filter(\.isObligatory)
    }

    // MARK: Widget

    /// Whether the widget shows the zone name.
    var widgetShowLocation: Bool {
        get { defaults.bool(forKey: PreferenceKeys.widgetShowLocation) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.widgetShowLocation) }
    }

    /// Whether the widget shows the "in 38 min" line.
    var widgetShowCountdown: Bool {
        get { defaults.bool(forKey: PreferenceKeys.widgetShowCountdown) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.widgetShowCountdown) }
    }

    /// Whether the widget shows the Hijri date.
    var widgetShowDate: Bool {
        get { defaults.bool(forKey: PreferenceKeys.widgetShowDate) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.widgetShowDate) }
    }

    /// The settings bundle handed to the widget.
    var widgetDisplaySettings: WidgetDisplaySettings {
        WidgetDisplaySettings(
            showSecondaryMarkers: showSecondaryMarkers,
            use24HourClock: use24HourClock,
            showLocation: widgetShowLocation,
            showCountdown: widgetShowCountdown,
            showDate: widgetShowDate
        )
    }

    // MARK: Coverage warnings

    /// When the user was last told the prayer times are going stale, so the
    /// warning doesn't repeat on every failed refresh.
    var lastCoverageWarning: Date? {
        get { defaults.object(forKey: PreferenceKeys.lastCoverageWarning) as? Date }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.lastCoverageWarning) }
    }
}
