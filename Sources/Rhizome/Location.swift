import CoreLocation

enum LocationError: Error { case unavailable }

/// One-shot "where am I right now" as async/await, bridging CLLocationManager's delegate.
/// Requests When-In-Use permission on first use (see Info.plist). Returns just the coordinate
/// (a Sendable value) so nothing non-Sendable crosses the actor hop.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cont: CheckedContinuation<CLLocationCoordinate2D, Error>?

    func current() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { c in
            self.cont = c
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()  // → authorization change requests the fix
            case .denied, .restricted: finish(.failure(LocationError.unavailable))
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let c = cont else { return }
        cont = nil
        c.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(.failure(LocationError.unavailable))
            default: break   // still undetermined → wait for the prompt result
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lat = locations.last?.coordinate.latitude   // capture plain Doubles across the hop
        let lon = locations.last?.coordinate.longitude
        Task { @MainActor in
            if let lat, let lon { self.finish(.success(CLLocationCoordinate2D(latitude: lat, longitude: lon))) }
            else { self.finish(.failure(LocationError.unavailable)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(LocationError.unavailable)) }
    }
}
