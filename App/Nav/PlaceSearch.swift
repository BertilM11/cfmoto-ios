// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import MapKit
import Combine

/// Búsqueda de direcciones y lugares con el buscador de Apple Maps.
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var busy = false

    private let completer = MKLocalSearchCompleter()
    private var active: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
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
        if let region = nearby() {
            completer.region = region
        }
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
        } else {
            results = Array(completer.results.prefix(7))
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
