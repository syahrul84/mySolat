import Foundation

/// What the widget should draw, shared with the widget as a file.
///
/// The widget is a sandboxed extension, so it reaches the app's settings through
/// the App Group. Reading `UserDefaults(suiteName:)` across that boundary has
/// proven unreliable here — an unset key silently falls back to the registered
/// default, so a setting turned off in the app kept showing in the widget.
///
/// The widget already reads `prayer-cache.json` from the group container without
/// trouble, so this travels the same proven path: the app writes the file on every
/// settings change, and the widget reads it. `UserDefaults` remains a fallback, so
/// nothing breaks if the file hasn't been written yet.
struct WidgetDisplaySettings: Codable, Equatable, Sendable {
    /// Whether Imsak, Syuruk and Dhuha appear in the list.
    var showSecondaryMarkers: Bool
    var use24HourClock: Bool

    /// The zone name, e.g. "Gombak, Petaling, Sepang…".
    var showLocation: Bool
    /// The "in 38 min" line under the next prayer.
    var showCountdown: Bool
    /// The Hijri date.
    var showDate: Bool

    static let `default` = WidgetDisplaySettings(
        showSecondaryMarkers: true,
        use24HourClock: false,
        showLocation: true,
        showCountdown: true,
        showDate: true
    )

    /// Markers the widget should list.
    var visiblePrayers: [Prayer] {
        showSecondaryMarkers ? Prayer.displayOrder : Prayer.displayOrder.filter(\.isObligatory)
    }

    static let fileName = "widget-settings.json"

    private static var fileURL: URL {
        SharedContainer.directory.appendingPathComponent(fileName)
    }

    /// Writes the file the widget reads. Called whenever settings change.
    @discardableResult
    static func write(_ settings: WidgetDisplaySettings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Reads the shared file, falling back to `UserDefaults` and then to defaults.
    ///
    /// The fallback matters on first run and for anyone upgrading from a build
    /// that never wrote the file.
    static func load(fallback prefs: Preferences = Preferences()) -> WidgetDisplaySettings {
        for directory in SharedContainer.readCandidates {
            let url = directory.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(WidgetDisplaySettings.self, from: data) {
                return decoded
            }
        }
        return prefs.widgetDisplaySettings
    }
}
