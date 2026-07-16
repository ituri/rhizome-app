import SwiftUI
import MapKit
import RhizomeKit

/// A small, non-interactive map pinning a coordinate — using OpenStreetMap tiles (like the web's
/// Leaflet map) laid over MapKit, not Apple Maps.
struct GeoMapView: View {
    let lat: Double
    let lon: Double

    var body: some View {
        OSMMapView(lat: lat, lon: lon)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .allowsHitTesting(false)
    }
}

/// A UIKit MKMapView whose base content is replaced by OSM tiles, with a single accent pin.
private struct OSMMapView: UIViewRepresentable {
    let lat: Double
    let lon: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.isUserInteractionEnabled = false

        let overlay = MKTileOverlay(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        overlay.canReplaceMapContent = true   // hide Apple's base map — show only OSM tiles
        overlay.maximumZ = 19
        map.addOverlay(overlay, level: .aboveLabels)

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        map.setRegion(MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500), animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = coord
        map.addAnnotation(pin)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard let pin = map.annotations.first(where: { !($0 is MKUserLocation) }) as? MKPointAnnotation else { return }
        if pin.coordinate.latitude != lat || pin.coordinate.longitude != lon {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            pin.coordinate = coord
            map.setRegion(MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500), animated: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tile) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "pin"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.image = Self.pinImage
            v.isUserInteractionEnabled = false
            return v
        }

        // an accent-coloured dot with a white ring, like the web's circle marker
        static let pinImage: UIImage = {
            UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
                let path = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 14, height: 14))
                rzAccentUIColor(RZTheme.accent).setFill(); path.fill()
                UIColor.white.setStroke(); path.lineWidth = 2; path.stroke()
            }
        }()
    }
}
