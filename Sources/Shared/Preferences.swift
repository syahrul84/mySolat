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
    static let notifyAtPrayerTime = "notifyAtPrayerTime"
    static let preAlertMinutes = "preAlertMinutes"
    static let preAlertEnabled = "preAlertEnabled"
    static let enabledPrayers = "enabledPrayers"
    static let notificationSoundEnabled = "notificationSoundEnabled"
    static let launchAtLogin = "launchAtLogin"
    static let autoUpdateCheck = "autoUpdateCheck"
    static let lastUpdateCheck = "lastUpdateCheck"
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
            PreferenceKeys.notifyAtPrayerTime: true,
            PreferenceKeys.preAlertEnabled: true,
            PreferenceKeys.preAlertMinutes: 15,
            PreferenceKeys.notificationSoundEnabled: true,
            PreferenceKeys.enabledPrayers: Prayer.allCases.filter(\.isObligatory).map(\.rawValue),
            PreferenceKeys.launchAtLogin: false,
            PreferenceKeys.autoUpdateCheck: true,
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

    var autoUpdateCheck: Bool {
        get { defaults.bool(forKey: PreferenceKeys.autoUpdateCheck) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.autoUpdateCheck) }
    }

    var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: PreferenceKeys.hasCompletedSetup) }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.hasCompletedSetup) }
    }

    /// Markers the UI should list, honouring `showSecondaryMarkers`.
    var visiblePrayers: [Prayer] {
        showSecondaryMarkers ? Prayer.displayOrder : Prayer.displayOrder.filter(\.isObligatory)
    }
}
