import Foundation

/// The list of JAKIM zones.
///
/// A snapshot ships inside the bundle (`zones.json`) so the zone picker and first
/// launch work with no network. `refresh()` replaces it from the API and caches the
/// result in the shared container.
final class ZoneCatalog {
    static let shared = ZoneCatalog()

    private(set) var zones: [Zone]
    private let cacheURL: URL

    private init() {
        cacheURL = SharedContainer.directory.appendingPathComponent("zones.json")
        zones = Self.loadCached(at: cacheURL) ?? Self.loadBundled() ?? []
    }

    /// Zones grouped by state, both sorted alphabetically for the picker.
    var groupedByNegeri: [(negeri: String, zones: [Zone])] {
        Dictionary(grouping: zones, by: \.negeri)
            .map { (negeri: $0.key, zones: $0.value.sorted { $0.jakimCode < $1.jakimCode }) }
            .sorted { $0.negeri < $1.negeri }
    }

    func zone(for code: String) -> Zone? {
        zones.first { $0.jakimCode.caseInsensitiveCompare(code) == .orderedSame }
    }

    /// Human-readable location for a code, degrading to the raw code if unknown.
    func describe(code: String) -> String {
        guard let zone = zone(for: code) else { return code }
        return "\(zone.daerah), \(zone.negeri)"
    }

    func search(_ query: String) -> [Zone] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return zones }
        return zones.filter { $0.searchText.contains(needle) }
    }

    /// Pulls the current zone list from the API. Failures are non-fatal — the
    /// bundled snapshot stays in use.
    @discardableResult
    func refresh(api: WaktuSolatAPI) async -> Bool {
        do {
            let fetched = try await api.fetchZones()
            guard !fetched.isEmpty else { return false }
            zones = fetched
            if let data = try? PrayerCacheFile.encoder().encode(fetched) {
                try? data.write(to: cacheURL, options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Loading

    private static func loadCached(at url: URL) -> [Zone]? {
        guard let data = try? Data(contentsOf: url),
              let zones = try? JSONDecoder().decode([Zone].self, from: data),
              !zones.isEmpty
        else { return nil }
        return zones
    }

    private static func loadBundled() -> [Zone]? {
        guard let url = Bundle.main.url(forResource: "zones", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let zones = try? JSONDecoder().decode([Zone].self, from: data)
        else { return nil }
        return zones
    }
}
