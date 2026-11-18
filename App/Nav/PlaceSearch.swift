// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import MapKit
import Combine

/// Un resultado del buscador: de Apple Maps (hay que pedir sus coordenadas) o del mapa de
/// OpenStreetMap que viene en la app (ya trae las coordenadas).
struct SearchItem {
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?
    let coordinate: CLLocationCoordinate2D?
}

/// Búsqueda de direcciones y lugares: sin internet en el mapa de Guatemala (modo
/// OpenStreetMap) o con el buscador de Apple Maps (modo Apple).
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published private(set) var results: [SearchItem] = []
    @Published private(set) var busy = false

    private let completer = MKLocalSearchCompleter()
    private var active: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// En el modo OpenStreetMap se busca en el mapa guardado: los resultados de Apple no se
    /// usan con un mapa que no es de Apple.
    var offline: Bool {
        DashStore.shared.config.map.provider == .osm && OSMMapData.current != nil
    }

    private func nearby() -> MKCoordinateRegion? {
        guard let c = LocationService.shared.last?.coordinate else { return nil }
        return MKCoordinateRegion(center: c, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }

    private func queryChanged() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            results = []
            return
        }
        if offline {
            let here = LocationService.shared.last.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
            let asked = query
            OSMSearchService.shared.search(asked, near: here) { [weak self] found in
                guard let self = self, self.query == asked else { return }
                self.results = found.map {
                    SearchItem(title: $0.title, subtitle: $0.subtitle, completion: nil,
                               coordinate: CLLocationCoordinate2D(latitude: $0.point.lat, longitude: $0.point.lon))
                }
            }
            return
        }
        if let region = nearby() {
            completer.region = region
        }
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !offline else { return }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
        } else {
            results = completer.results.prefix(7).map {
                SearchItem(title: $0.title, subtitle: $0.subtitle, completion: $0, coordinate: nil)
            }
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Suele ocurrir al escribir rápido o sin conexión; se conserva la última lista.
    }

    /// Convierte una sugerencia en un lugar con coordenadas.
    func resolve(_ completion: MKLocalSearchCompletion, done: @escaping (MKMapItem?) -> Void) {
        run(MKLocalSearch.Request(completion: completion), done: done)
    }

    /// Busca el texto tal cual (tecla "Buscar" del teclado).
    func resolve(text: String, done: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let region = nearby() {
            request.region = region
        }
        run(request, done: done)
    }

    private func run(_ request: MKLocalSearch.Request, done: @escaping (MKMapItem?) -> Void) {
        active?.cancel()
        busy = true
        let search = MKLocalSearch(request: request)
        active = search
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                self?.busy = false
                done(response?.mapItems.first)
            }
        }
    }

    func clear() {
        query = ""
        results = []
    }
}

/// La búsqueda sin internet: arma el índice del mapa de Guatemala una sola vez, fuera del hilo
/// principal, y responde a cada letra escrita.
final class OSMSearchService {
    static let shared = OSMSearchService()
    private let queue = DispatchQueue(label: "cfmoto.osm.busqueda", qos: .userInitiated)
    private var index: OSMSearch?

    private func ready() -> OSMSearch? {
        if index == nil, let map = OSMMapData.current {
            let started = Date()
            let built = OSMSearch(map: map)
            index = built
            logLine(String(format: "[BUSCAR] índice sin internet: %d lugares en %.2f s", built.count, Date().timeIntervalSince(started)))
        }
        return index
    }

    /// Prepara el índice antes de la primera búsqueda (al abrir el buscador).
    func warmUp() {
        queue.async { _ = self.ready() }
    }

    func search(_ text: String, near: GeoPoint?, done: @escaping ([OSMSearchResult]) -> Void) {
        queue.async {
            let found = self.ready()?.search(text, near: near) ?? []
            DispatchQueue.main.async { done(found) }
        }
    }
}
