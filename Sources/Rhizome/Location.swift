import CoreLocation

/// A retained location provider that keeps the latest coordinate warm while you edit, so the
/// geo button can read a cached fix instead of waiting on a one-shot request (which could hang
/// and leave the button stuck). Nothing here can block: the button polls `current` with a bound.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var current: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Human-readable auth status (for the geo diagnostic alert).
    var authStatusText: String {
        switch manager.authorizationStatus {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorizedWhenInUse: return "whenInUse"
        case .authorizedAlways: return "always"
        @unknown default: return "unknown"
        }
    }

    /// Begin warming up (called when editing starts): prompt for permission if needed and start
    /// standard updates so `current` fills in within a second or two.
    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lat = locations.last?.coordinate.latitude
        let lon = locations.last?.coordinate.longitude
        Task { @MainActor in if let lat, let lon { self.current = CLLocationCoordinate2D(latitude: lat, longitude: lon) } }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {   // use self.manager (Sendable) — not the param
            case .authorizedWhenInUse, .authorizedAlways: self.manager.startUpdatingLocation()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
