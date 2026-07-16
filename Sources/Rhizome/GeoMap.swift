import SwiftUI
import MapKit

/// A small, non-interactive map pinning a coordinate — the native equivalent of the web's Leaflet
/// mini-map shown under a bullet that references a location page.
struct GeoMapView: View {
    let lat: Double
    let lon: Double

    var body: some View {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500)),
            interactionModes: []) {
            Annotation("", coordinate: coord) {
                Circle()
                    .fill(Color.rzAccent)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }
}
