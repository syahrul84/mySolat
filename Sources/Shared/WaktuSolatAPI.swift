import Foundation

enum SolatAPIError: LocalizedError {
    case badResponse(status: Int)
    case decoding(underlying: Error)
    case noZoneForCoordinates

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "The prayer time service returned an unexpected response (HTTP \(status))."
        case .decoding:
            return "The prayer time data could not be read. The service may have changed format."
        case .noZoneForCoordinates:
            return "No Malaysian prayer zone matches your current location."
        }
    }
}

/// Client for https://api.waktusolat.app
///
/// Endpoints used:
///  - `GET /zones`                        → every JAKIM zone
///  - `GET /v2/solat/{zone}?year=&month=` → one calendar month for a zone
///  - `GET /v2/solat/gps/{lat}/{long}`    → zone detection from coordinates
struct WaktuSolatAPI: Sendable {
    static let baseURL = URL(string: "https://api.waktusolat.app")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A session tuned for a background-ish fetch: short timeouts so a bad
    /// network doesn't leave the menu bar spinning, and the system cache honoured.
    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadRevalidatingCacheData
        return URLSession(configuration: config)
    }

    // MARK: Requests

    func fetchZones() async throws -> [Zone] {
        let url = Self.baseURL.appendingPathComponent("zones")
        return try await get(url, as: [Zone].self)
    }

    /// One calendar month of prayer times for a zone.
    func fetchMonth(zone: String, year: Int, month: Int) async throws -> MonthlyPrayerResponse {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("v2/solat/\(zone)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "month", value: String(month)),
        ]
        return try await get(components.url!, as: MonthlyPrayerResponse.self)
    }

    /// Resolves a JAKIM zone code from GPS coordinates.
    func detectZone(latitude: Double, longitude: Double) async throws -> String {
        let lat = String(format: "%.5f", latitude)
        let lon = String(format: "%.5f", longitude)
        let url = Self.baseURL.appendingPathComponent("v2/solat/gps/\(lat)/\(lon)")

        // The GPS endpoint returns either a zone descriptor or a full monthly
        // payload depending on API version, so try both shapes.
        let data = try await rawGet(url)
        if let zoneResponse = try? PrayerCacheFile.decoder().decode(GPSZoneResponse.self, from: data),
           let code = zoneResponse.resolvedZoneCode, !code.isEmpty {
            return code
        }
        if let monthly = try? JSONDecoder().decode(MonthlyPrayerResponse.self, from: data),
           !monthly.zone.isEmpty {
            return monthly.zone
        }
        throw SolatAPIError.noZoneForCoordinates
    }

    // MARK: Transport

    private func rawGet(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("mySolat/\(AppVersion.short) (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SolatAPIError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SolatAPIError.badResponse(status: http.statusCode)
        }
        return data
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let data = try await rawGet(url)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SolatAPIError.decoding(underlying: error)
        }
    }
}

// MARK: - Response → stored model

extension MonthlyPrayerResponse {
    /// Flattens the API's per-month payload into `PrayerDay` values keyed by the
    /// Malaysian day boundary.
    ///
    /// Days whose date can't be constructed, or that carry no usable timestamps,
    /// are dropped rather than stored as empty rows.
    func toPrayerDays() -> [PrayerDay] {
        let cal = SolatCalendar.zoneCalendar
        return prayers.compactMap { apiDay -> PrayerDay? in
            var components = DateComponents()
            components.year = year
            components.month = monthNumber
            components.day = apiDay.day
            components.hour = 0
            components.minute = 0
            components.timeZone = SolatCalendar.zoneTimeZone
            guard let dayStart = cal.date(from: components) else { return nil }

            var times: [String: Date] = [:]
            for prayer in Prayer.allCases {
                guard let ts = apiDay.timestamp(for: prayer), ts > 0 else { continue }
                times[prayer.rawValue] = Date(timeIntervalSince1970: ts)
            }
            guard !times.isEmpty else { return nil }

            return PrayerDay(date: dayStart, hijri: apiDay.hijri, times: times)
        }
    }
}
