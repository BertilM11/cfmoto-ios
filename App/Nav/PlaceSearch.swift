// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import MapKit
import Combine

/// Un resultado del buscador: de Apple Maps (hay que pedir sus coordenadas), del mapa de
/// OpenStreetMap que viene en la app, de la búsqueda en internet, de los destinos guardados
/// o de unas coordenadas pegadas (estos ya traen las coordenadas).
struct SearchItem {
    enum Kind: Equatable {
        case place
        case saved(SavedPlace.Kind)
        case recent
        /// Coordenadas o enlace pegados.
        case pasted
        /// Fila «Buscar en internet».
        case online(String)
        /// Enlace corto que se está abriendo.
        case opening
        /// Solo un aviso (no lleva a ningún lado).
        case note
    }

    var kind: Kind = .place
    let title: String
    let subtitle: String
    var completion: MKLocalSearchCompletion? = nil
    var coordinate: CLLocationCoordinate2D? = nil

    var icon: String {
        switch kind {
        case .place: return "mappin.circle.fill"
        case .saved(let k): return k.icon
        case .recent: return "clock.arrow.circlepath"
        case .pasted: return "scope"
        case .online: return "globe.americas.fill"
        case .opening: return "link"
        case .note: return "info.circle"
        }
    }
}

/// Búsqueda de direcciones y lugares: sin internet en el mapa de Guatemala (modo
/// OpenStreetMap) o con el buscador de Apple Maps (modo Apple). 0.7.2: además entiende
/// coordenadas y enlaces de mapas pegados, busca en los destinos guardados y, si se pide,
/// en OpenStreetMap por internet.
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published private(set) var results: [SearchItem] = []
    @Published private(set) var busy = false
    /// La lista viene de la búsqueda en internet (se muestra su aviso de OpenStreetMap).
    @Published private(set) var showingOnline = false

    private let completer = MKLocalSearchCompleter()
    private var active: MKLocalSearch?
    private var onlineTask: URLSessionDataTask?
    private var linkResolver: ShortLinkResolver?
    private var lastOnline = Date.distantPast

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

    private var here: GeoPoint? {
        LocationService.shared.last.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
    }

    private func nearby() -> MKCoordinateRegion? {
        guard let c = LocationService.shared.last?.coordinate else { return nil }
        return MKCoordinateRegion(center: c, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }

    static func coordText(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.5f, %.5f", lat, lon)
    }

    private func stopPending() {
        onlineTask?.cancel()
        onlineTask = nil
        linkResolver?.cancel()
        linkResolver = nil
        showingOnline = false
        busy = false
    }

    /// Destinos guardados y recientes cuyo nombre coincide con lo escrito.
    private func savedMatches(_ text: String) -> [SearchItem] {
        let q = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard q.count >= 2 else { return [] }
        let places = SavedPlaces.shared
        var out: [SearchItem] = []
        for p in places.ordered where p.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) {
            out.append(SearchItem(kind: .saved(p.kind), title: p.name, subtitle: "Guardado", coordinate: p.coordinate))
        }
        for p in places.recent where out.count < 3
            && places.savedMatch(lat: p.lat, lon: p.lon) == nil
            && p.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) {
            out.append(SearchItem(kind: .recent, title: p.name, subtitle: "Reciente", coordinate: p.coordinate))
        }
        return Array(out.prefix(3))
    }

    private func onlineRow(_ text: String) -> SearchItem? {
        guard text.count >= 3 else { return nil }
        return SearchItem(kind: .online(text), title: "Buscar «\(text)» en internet",
                          subtitle: "OpenStreetMap en línea: más direcciones y lugares")
    }

    private func queryChanged() {
        stopPending()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            results = []
            return
        }
        // Coordenadas o enlace de mapas pegados.
        if let parsed = PlaceInput.parse(text) {
            switch parsed {
            case let .coordinate(lat, lon, name):
                results = [pastedItem(lat, lon, name)]
            case let .shortLink(url):
                results = [SearchItem(kind: .opening, title: "Abriendo el enlace…", subtitle: "Buscando el punto marcado (necesita internet)")]
                openShortLink(url, name: PlaceInput.nameBeforeLink(text))
            case .unreadableLink:
                results = [SearchItem(kind: .note, title: "Este enlace no trae coordenadas",
                                      subtitle: "En Google Maps mantené presionado el lugar y copiá los números (14.63, -90.50)")]
            }
            return
        }
        let mine = savedMatches(text)
        if offline {
            let asked = query
            results = mine + [onlineRow(text)].compactMap { $0 }
            OSMSearchService.shared.search(asked, near: here) { [weak self] found in
                guard let self = self, self.query == asked, !self.showingOnline else { return }
                let local = found.map {
                    SearchItem(title: $0.title, subtitle: $0.subtitle,
                               coordinate: CLLocationCoordinate2D(latitude: $0.point.lat, longitude: $0.point.lon))
                }
                let shown: [SearchItem] = Array(local.prefix(max(3, 7 - mine.count)))
                self.results = mine + shown + [self.onlineRow(text)].compactMap { $0 }
            }
            return
        }
        results = mine
        if let region = nearby() {
            completer.region = region
        }
        completer.queryFragment = text
    }

    private func pastedItem(_ lat: Double, _ lon: Double, _ name: String?) -> SearchItem {
        let saved = SavedPlaces.shared.savedMatch(lat: lat, lon: lon)
        return SearchItem(kind: .pasted, title: name ?? saved?.name ?? "Punto de las coordenadas",
                          subtitle: Self.coordText(lat, lon) + " · tocá para ver la ruta",
                          coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    private func openShortLink(_ url: URL, name: String?) {
        busy = true
        let asked = query
        let resolver = ShortLinkResolver()
        linkResolver = resolver
        logLine("[BUSCAR] abriendo enlace corto \(url.host ?? "")")
        resolver.resolve(url, done: { [weak self] lat, lon, linkName in
            guard let self = self, self.query == asked else { return }
            self.busy = false
            self.results = [self.pastedItem(lat, lon, linkName ?? name)]
            logLine("[BUSCAR] enlace corto → \(Self.coordText(lat, lon))")
        }, fail: { [weak self] in
            guard let self = self, self.query == asked else { return }
            self.busy = false
            self.results = [SearchItem(kind: .note, title: "No se pudo leer el enlace",
                                       subtitle: "Revisá el internet, o en Google Maps copiá las coordenadas del lugar")]
            logLine("[BUSCAR] enlace corto sin coordenadas")
        })
    }

    /// Búsqueda en internet en OpenStreetMap (al tocar «Buscar en internet»).
    func searchOnline(_ text: String) {
        let wait = 1.1 - Date().timeIntervalSince(lastOnline)   // máximo una consulta por segundo
        if wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.searchOnline(text) }
            return
        }
        lastOnline = Date()
        onlineTask?.cancel()
        busy = true
        showingOnline = true
        let asked = query
        let mine = savedMatches(text)
        onlineTask = OnlineSearch.search(text, near: here) { [weak self] found in
            guard let self = self, self.query == asked else { return }
            self.busy = false
            guard let found = found else {
                self.results = mine + [SearchItem(kind: .note, title: "Sin conexión a internet",
                                                  subtitle: "La búsqueda en el mapa guardado sigue funcionando")]
                return
            }
            logLine("[BUSCAR] en internet «\(text)»: \(found.count) resultado(s)")
            if found.isEmpty {
                self.results = mine + [SearchItem(kind: .note, title: "Tampoco aparece en internet",
                                                  subtitle: "Probá con otro nombre, o pegá las coordenadas o el enlace de Google Maps")]
                return
            }
            self.results = mine + found.map {
                SearchItem(title: $0.title, subtitle: $0.subtitle,
                           coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon))
            }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !offline else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || PlaceInput.parse(text) != nil {
            if text.isEmpty { results = [] }
            return
        }
        let mine = savedMatches(text)
        results = mine + completer.results.prefix(7 - mine.count).map {
            SearchItem(title: $0.title, subtitle: $0.subtitle, completion: $0)
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
