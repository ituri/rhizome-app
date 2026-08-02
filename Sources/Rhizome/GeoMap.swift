import SwiftUI
import MapKit
import RhizomeKit

/// Mainland Norway, approximated by two boxes — Kartverket serves blank tiles outside its
/// coverage, so the check must stay inside the country (mirrors the web's inNorway()).
func rzInNorway(_ lat: Double, _ lon: Double) -> Bool {
    (lat >= 57.9 && lat < 65 && lon >= 4.5 && lon <= 14.5)
        || (lat >= 65 && lat <= 71.4 && lon >= 11 && lon <= 31.5)
}

/// A small, non-interactive map pinning a coordinate — raster tiles laid over MapKit, not Apple
/// Maps. Norwegian coordinates render on Kartverket's topo tiles with a wide terrain view (like
/// sotl.as); `topo` forces the topo look elsewhere too (SOTA summits → OpenTopoMap).
struct GeoMapView: View {
    let lat: Double
    let lon: Double
    var topo = false

    var body: some View {
        OSMMapView(lat: lat, lon: lon, topo: topo)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .allowsHitTesting(false)
    }
}

/// A UIKit MKMapView whose base content is replaced by raster tiles, with a single accent pin.
private struct OSMMapView: UIViewRepresentable {
    let lat: Double
    let lon: Double
    let topo: Bool

    // tile source + span follow the coordinate: Norway → Kartverket topo, wide; SOTA-topo
    // elsewhere → OpenTopoMap, wide; everything else → OSM at street level
    private var template: String {
        if rzInNorway(lat, lon) {
            return "https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png"
        }
        return topo ? "https://tile.opentopomap.org/{z}/{x}/{y}.png"
                    : "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    }
    private var maxZ: Int { rzInNorway(lat, lon) ? 18 : topo ? 17 : 19 }
    private var meters: CLLocationDistance { rzInNorway(lat, lon) || topo ? 15000 : 500 }

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

        applyOverlay(map, context: context)
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        map.setRegion(MKCoordinateRegion(center: coord, latitudinalMeters: meters, longitudinalMeters: meters), animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = coord
        map.addAnnotation(pin)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if context.coordinator.template != template { applyOverlay(map, context: context) }
        guard let pin = map.annotations.first(where: { !($0 is MKUserLocation) }) as? MKPointAnnotation else { return }
        if pin.coordinate.latitude != lat || pin.coordinate.longitude != lon {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            pin.coordinate = coord
            map.setRegion(MKCoordinateRegion(center: coord, latitudinalMeters: meters, longitudinalMeters: meters), animated: false)
        }
    }

    private func applyOverlay(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = true   // hide Apple's base map — show only the raster tiles
        overlay.maximumZ = maxZ
        map.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.template = template
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var template = ""

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

// MARK: - SOTA summit mini map

/// Resolves a SOTA reference (LA/FM-178) to its summit coordinates via the official SOTA API,
/// cached persistently — one fetch per summit, ever (mirrors the web's localStorage cache).
enum SotaLookup {
    private static let cacheKey = "sota-coords"

    static func cached(_ ref: String) -> (lat: Double, lon: Double)? {
        guard let d = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [Double]],
              let c = d[ref], c.count == 2 else { return nil }
        return (c[0], c[1])
    }

    static func coords(for ref: String) async -> (lat: Double, lon: Double)? {
        if let c = cached(ref) { return c }
        struct Summit: Decodable { let latitude: Double; let longitude: Double }
        guard let url = URL(string: "https://api2.sota.org.uk/api/summits/" + ref),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let s = try? JSONDecoder().decode(Summit.self, from: data) else { return nil }
        var d = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [Double]]) ?? [:]
        d[ref] = [s.latitude, s.longitude]
        UserDefaults.standard.set(d, forKey: cacheKey)
        return (s.latitude, s.longitude)
    }
}

/// The inline mini map for a bullet linking a sotl.as summit — topo tiles, wide terrain view.
struct SotaMapView: View {
    let ref: String
    @State private var lat: Double?
    @State private var lon: Double?

    var body: some View {
        Group {
            if let lat, let lon { GeoMapView(lat: lat, lon: lon, topo: true) }
        }
        .task(id: ref) {
            if let c = await SotaLookup.coords(for: ref) {   // cache-first internally
                lat = c.lat; lon = c.lon
            }
        }
    }
}
