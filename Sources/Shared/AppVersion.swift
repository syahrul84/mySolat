import Foundation

/// Version info read from the bundle, with a comparable semantic form.
enum AppVersion {
    /// Marketing version, e.g. `1.0.0`.
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Build number, e.g. `12`. Sparkle compares this.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var displayString: String { "\(short) (\(build))" }

    /// Compares dotted numeric versions, tolerating a leading `v` and any
    /// trailing pre-release suffix. Returns true when `candidate` is newer.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = numericComponents(lhs)
        let r = numericComponents(rhs)
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericComponents(_ version: String) -> [Int] {
        var trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") { trimmed.removeFirst() }
        // Stop at the first pre-release separator so `1.2.0-beta.1` → [1, 2, 0].
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? trimmed
        return core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
