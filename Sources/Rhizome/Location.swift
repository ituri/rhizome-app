import CoreLocation

enum LocationError: Error { case unavailable }

/// Current coordinate via the modern async location stream (iOS 17+). Prompts for When-In-Use
/// permission if needed (see Info.plist), yields the first fix, and — crucially — times out, so
/// the geo button never sticks in its spinning state when no fix arrives.
enum Location {
    private struct Coord: Sendable { let latitude: Double; let longitude: Double }

    static func current() async throws -> CLLocationCoordinate2D {
        let c = try await withThrowingTaskGroup(of: Coord.self) { group -> Coord in
            group.addTask { try await firstFix() }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)   // 15s safety net
                throw LocationError.unavailable
            }
            defer { group.cancelAll() }
            guard let coord = try await group.next() else { throw LocationError.unavailable }
            return coord
        }
        return CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    private static func firstFix() async throws -> Coord {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let loc = update.location {
                return Coord(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            }
            if update.authorizationDenied { throw LocationError.unavailable }
        }
        throw LocationError.unavailable
    }
}
