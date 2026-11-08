import Foundation

/// Identifiers shared by the app and the widget extension.
enum AppIdentifiers {
    static let appBundleID = "com.ginlabs.mysolat"
    static let widgetBundleID = "com.ginlabs.mysolat.SolatWidget"
    static let widgetKind = "com.ginlabs.mysolat.PrayerWidget"
    /// macOS App Groups are prefixed with the Team ID so they also work on macOS 13 and 14.
    static let appGroup = "3UZAQDJ7T4.group.com.ginlabs.mysolat"

    static let repoOwner = "syahrul84"
    static let repoName = "mySolat"
    static var repoURL: URL { URL(string: "https://github.com/\(repoOwner)/\(repoName)")! }
    static var licenseURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/blob/main/LICENSE")!
    }

    /// Shown in the About pane and the bundle's copyright field.
    static let authorName = "Syahrul Farhan"
    static let licenseName = "MIT License"
}

/// Where the app and the widget meet on disk.
///
/// A macOS widget extension is sandboxed, so it cannot read the app's normal
/// Application Support directory. We therefore prefer the App Group container.
/// Ad-hoc-signed builds don't always get one, so this falls back to
/// `~/Library/Application Support/mySolat` — and the widget additionally knows how
/// to fetch from the network itself, so it still works if neither path is shared.
enum SharedContainer {
    /// Directory to read/write the prayer cache in. Never throws; falls back to a
    /// temporary directory as a last resort so callers don't need error handling.
    static var directory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup) {
            let dir = group.appendingPathComponent("Library/Caches", isDirectory: true)
            if ensureDirectory(dir) { return dir }
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = support.appendingPathComponent("mySolat", isDirectory: true)
            if ensureDirectory(dir) { return dir }
        }
        return FileManager.default.temporaryDirectory
    }

    /// Directories to *read* from, in priority order. Writing goes to `directory`,
    /// but a build that loses its group container should still find an older cache.
    static var readCandidates: [URL] {
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup) {
            urls.append(group.appendingPathComponent("Library/Caches", isDirectory: true))
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(support.appendingPathComponent("mySolat", isDirectory: true))
        }
        return urls
    }

    static let cacheFileName = "prayer-cache.json"

    private static func ensureDirectory(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// `UserDefaults` shared with the widget, falling back to the app's own
    /// defaults when no group container is available.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }
}

/// Reads and writes the prayer cache JSON. Used by both the app and the widget.
struct PrayerCacheFile {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Loads the newest readable cache across every candidate directory.
    static func load() -> PrayerCache? {
        var best: PrayerCache?
        for dir in SharedContainer.readCandidates {
            let url = dir.appendingPathComponent(SharedContainer.cacheFileName)
            guard let data = try? Data(contentsOf: url),
                  let cache = try? decoder().decode(PrayerCache.self, from: data)
            else { continue }
            if best == nil || cache.fetchedAt > best!.fetchedAt { best = cache }
        }
        return best
    }

    static func save(_ cache: PrayerCache) throws {
        let dir = SharedContainer.directory
        let url = dir.appendingPathComponent(SharedContainer.cacheFileName)
        let data = try encoder().encode(cache)
        try data.write(to: url, options: .atomic)
    }
}
