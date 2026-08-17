import CoreLocation
import Foundation

/// One-shot "where am I" helper used by the zone auto-detect button.
///
/// Location is strictly opt-in: nothing here runs until the user taps Detect, and
/// the coordinate is used for a single API call and never stored.
@MainActor
final class LocationResolver: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum ResolveError: LocalizedError {
        case denied
        case unavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access is off. Enable it in System Settings › Privacy & Security › Location Services, or pick your zone manually."
            case .unavailable:
                return "Your location could not be determined. Please pick your zone manually."
            case .timedOut:
                return "Finding your location took too long. Please pick your zone manually."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Requests permission if needed and returns a single fix.
    func currentLocation(timeout: TimeInterval = 15) async throws -> CLLocation {
        if case .denied = manager.authorizationStatus { throw ResolveError.denied }
        if case .restricted = manager.authorizationStatus { throw ResolveError.denied }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.requestLocation()

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run { self?.finish(.failure(ResolveError.timedOut)) }
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(ResolveError.unavailable))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            finish(.failure(ResolveError.denied))
        } else {
            finish(.failure(ResolveError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(.failure(ResolveError.denied))
        case .authorized, .authorizedAlways:
            // Permission just granted — the pending requestLocation() will deliver.
            manager.requestLocation()
        default:
            break
        }
    }
}
