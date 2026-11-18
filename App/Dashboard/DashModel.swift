// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Modelo del panel para la moto: módulos, plantillas, modos, perfiles y reglas.
// Sin UIKit: lo comparten la app, la vista previa, la transmisión y las pruebas.
import Foundation
import CoreGraphics

enum DashModule: String, Codable, CaseIterable, Identifiable {
    case nav, turn, map, trip, music, notices, clock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nav: return "Navegación"
        case .turn: return "Próximo giro"
        case .map: return "Mapa de ruta"
        case .trip: return "Viaje"
        case .music: return "Música"
        case .notices: return "Avisos"
        case .clock: return "Reloj"
        }
    }
    var symbol: String {
        switch self {
        case .nav: return "location.north.line.fill"
        case .turn: return "arrow.turn.up.right"
        case .map: return "map.fill"
        case .trip: return "flag.checkered"
        case .music: return "music.note"
        case .notices: return "bell.fill"
        case .clock: return "clock.fill"
        }
    }
    var showsRoute: Bool { self == .nav || self == .turn || self == .map }
}

enum DashTemplate: String, Codable, CaseIterable, Identifiable {
    /// Mapa en toda la imagen con tarjetas flotantes encima.
    case overlay
    case full, columns, mainSide
    var id: String { rawValue }
    var slotCount: Int {
        switch self {
        case .overlay: return 0
        case .full: return 1
        case .columns: return 2
        case .mainSide: return 3
        }
    }
    var title: String {
        switch self {
        case .overlay: return "Mapa completo"
        case .full: return "1 zona"
        case .columns: return "2 columnas"
        case .mainSide: return "Principal + 2"
        }
    }
    var shortTitle: String {
        switch self {
        case .overlay: return "Mapa"
        case .full: return "1 zona"
        case .columns: return "2 col."
        case .mainSide: return "1 + 2"
        }
    }
}

/// Esquina o borde donde va una tarjeta flotante sobre el mapa.
enum CardSpot: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomCenter, bottomRight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeft: return "Arriba izq."
        case .topRight: return "Arriba der."
        case .bottomLeft: return "Abajo izq."
        case .bottomCenter: return "Abajo centro"
        case .bottomRight: return "Abajo der."
        }
    }
    var isTop: Bool { self == .topLeft || self == .topRight }
    /// Parte de la imagen (0…1) donde se puede soltar una tarjeta para mandarla aquí.
    var region: CGRect {
        switch self {
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 1 / 3.0, height: 0.5)
        case .bottomCenter: return CGRect(x: 1 / 3.0, y: 0.5, width: 1 / 3.0, height: 0.5)
        case .bottomRight: return CGRect(x: 2 / 3.0, y: 0.5, width: 1 / 3.0, height: 0.5)
        }
    }
}

enum CardSize: String, Codable, CaseIterable, Identifiable {
    case compact, large
    var id: String { rawValue }
    var title: String { self == .compact ? "Compacta" : "Grande" }
}

/// Qué tarjetas van sobre el mapa y dónde (plantilla "Mapa completo").
struct OverlaySettings: Codable, Equatable {
    var maneuver = true
    var maneuverSpot: CardSpot = .topLeft
    var maneuverSize: CardSize = .compact
    var music = true
    var musicSpot: CardSpot = .topRight
    var musicSize: CardSize = .compact
    var trip = true
    var tripSpot: CardSpot = .bottomCenter
    var notices = true
    var noticesSpot: CardSpot = .topRight
    var clock = false
    var clockSpot: CardSpot = .bottomLeft

    init() {}

    init(maneuver: Bool = true, music: Bool, notices: Bool, trip: Bool = true, clock: Bool = false) {
        self.maneuver = maneuver
        self.music = music
        self.notices = notices
        self.trip = trip
        self.clock = clock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OverlaySettings()
        maneuver = (try? c.decode(Bool.self, forKey: .maneuver)) ?? d.maneuver
        maneuverSpot = (try? c.decode(CardSpot.self, forKey: .maneuverSpot)) ?? d.maneuverSpot
        maneuverSize = (try? c.decode(CardSize.self, forKey: .maneuverSize)) ?? d.maneuverSize
        music = (try? c.decode(Bool.self, forKey: .music)) ?? d.music
        musicSpot = (try? c.decode(CardSpot.self, forKey: .musicSpot)) ?? d.musicSpot
        musicSize = (try? c.decode(CardSize.self, forKey: .musicSize)) ?? d.musicSize
        trip = (try? c.decode(Bool.self, forKey: .trip)) ?? d.trip
        tripSpot = (try? c.decode(CardSpot.self, forKey: .tripSpot)) ?? d.tripSpot
        notices = (try? c.decode(Bool.self, forKey: .notices)) ?? d.notices
        noticesSpot = (try? c.decode(CardSpot.self, forKey: .noticesSpot)) ?? d.noticesSpot
        clock = (try? c.decode(Bool.self, forKey: .clock)) ?? d.clock
        clockSpot = (try? c.decode(CardSpot.self, forKey: .clockSpot)) ?? d.clockSpot
    }
}

enum OverlayItem: String, CaseIterable {
    /// `time`: la hora actual, fija arriba a la derecha en todos los modos (0.6.2). No se mueve
    /// ni se oculta, para no confundirla con la hora de llegada.
    case maneuver, music, trip, notices, clock, compass, time

    static let editable: [OverlayItem] = [.maneuver, .music, .trip, .notices, .clock]

    var title: String {
        switch self {
        case .maneuver: return "Próxima maniobra"
        case .music: return "Música"
        case .trip: return "Llegada y distancia"
        case .notices: return "Avisos"
        case .clock: return "Reloj"
        case .compass: return "Brújula"
        case .time: return "Hora actual"
        }
    }
    var symbol: String {
        switch self {
        case .maneuver: return "arrow.turn.up.right"
        case .music: return "music.note"
        case .trip: return "flag.checkered"
        case .notices: return "bell.fill"
        case .clock: return "clock.fill"
        case .compass: return "location.north.fill"
        case .time: return "clock"
        }
    }
    var resizable: Bool { self == .maneuver || self == .music }
}

extension OverlaySettings {
    func isOn(_ item: OverlayItem) -> Bool {
        switch item {
        case .maneuver: return maneuver
        case .music: return music
        case .trip: return trip
        case .notices: return notices
        case .clock: return clock
        case .compass, .time: return true
        }
    }

    mutating func set(_ item: OverlayItem, on: Bool) {
        switch item {
        case .maneuver: maneuver = on
        case .music: music = on
        case .trip: trip = on
        case .notices: notices = on
        case .clock: clock = on
        case .compass, .time: break
        }
    }

    func spot(_ item: OverlayItem) -> CardSpot {
        switch item {
        case .maneuver: return maneuverSpot
        case .music: return musicSpot
        case .trip: return tripSpot
        case .notices: return noticesSpot
        case .clock: return clockSpot
        case .compass: return .bottomRight
        case .time: return .topRight
        }
    }

    mutating func move(_ item: OverlayItem, to spot: CardSpot) {
        switch item {
        case .maneuver: maneuverSpot = spot
        case .music: musicSpot = spot
        case .trip: tripSpot = spot
        case .notices: noticesSpot = spot
        case .clock: clockSpot = spot
        case .compass, .time: return
        }
        set(item, on: true)
    }

    mutating func swap(_ a: OverlayItem, _ b: OverlayItem) {
        let sa = spot(a)
        let sb = spot(b)
        move(a, to: sb)
        move(b, to: sa)
    }

    func size(_ item: OverlayItem) -> CardSize {
        switch item {
        case .maneuver: return maneuverSize
        case .music: return musicSize
        default: return .compact
        }
    }

    mutating func resize(_ item: OverlayItem, to size: CardSize) {
        switch item {
        case .maneuver: maneuverSize = size
        case .music: musicSize = size
        default: break
        }
    }
}

struct OverlayCard: Equatable {
    let item: OverlayItem
    let rect: CGRect
}

enum MusicProvider: String, Codable, CaseIterable, Identifiable {
    case appleMusic, spotify
    var id: String { rawValue }
    var title: String { self == .appleMusic ? "Apple Music" : "Spotify" }
}

enum DashMode: String, Codable, CaseIterable, Identifiable {
    case gps, gpsMusic, split, music, custom, full, gpsNotices, musicNotices
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gps: return "Navegación completa"
        case .gpsMusic: return "Navegación + música compacta"
        case .split: return "Pantalla dividida"
        case .music: return "Música completa"
        case .custom: return "Personalizado"
        case .full: return "Panel completo"
        case .gpsNotices: return "Navegación + Avisos"
        case .musicNotices: return "Música + Avisos"
        }
    }
    /// Número de los cinco modos principales.
    var number: Int? {
        switch self {
        case .gps: return 1
        case .gpsMusic: return 2
        case .split: return 3
        case .music: return 4
        case .custom: return 5
        default: return nil
        }
    }
    var label: String { number.map { "\($0) · \(title)" } ?? title }
    var short: String {
        switch self {
        case .gps: return "1 · Navegación"
        case .gpsMusic: return "2 · Nav + Música"
        case .split: return "3 · Dividida"
        case .music: return "4 · Música"
        case .custom: return "5 · Personal"
        case .full: return "Completo"
        case .gpsNotices: return "Nav + Avisos"
        case .musicNotices: return "Música + Avisos"
        }
    }
    static let primary: [DashMode] = [.gps, .gpsMusic, .split, .music, .custom]
    static let others: [DashMode] = [.full, .gpsNotices, .musicNotices]
}

/// Quién da la guía giro a giro.
enum NavProviderID: String, Codable, CaseIterable, Identifiable {
    case cfmoto, appleMaps, googleMaps, waze
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cfmoto: return "CFMoto Link"
        case .appleMaps: return "Mapas de Apple"
        case .googleMaps: return "Google Maps"
        case .waze: return "Waze"
        }
    }
    var symbol: String {
        switch self {
        case .cfmoto: return "location.north.circle.fill"
        case .appleMaps: return "map.fill"
        case .googleMaps: return "mappin.circle.fill"
        case .waze: return "car.circle.fill"
        }
    }
    var external: Bool { self != .cfmoto }
    /// Esquema para saber si la app está instalada (nil: siempre disponible).
    var scheme: String? {
        switch self {
        case .cfmoto, .appleMaps: return nil
        case .googleMaps: return "comgooglemaps"
        case .waze: return "waze"
        }
    }

    /// Lo que de verdad puede hacer cada proveedor con esta app (sin suponer acceso a datos
    /// de otras apps).
    var capabilities: [(String, Bool)] {
        switch self {
        case .cfmoto:
            return [("Mapa de calles en la moto", true), ("Giros en la moto", true), ("Voz en español", true),
                    ("Funciona con el iPhone bloqueado", true), ("Tráfico en el mapa (Apple)", true)]
        case .appleMaps, .googleMaps, .waze:
            return [("Mapa de calles en la moto", true), ("Giros en la moto", false), ("Guía y voz en su app", true),
                    ("Destino en la moto", true), ("Ver su app en la moto (Duplicar pantalla, iPhone desbloqueado)", true)]
        }
    }

    /// Enlace oficial para abrir la ruta en la app de ese proveedor.
    func link(lat: Double, lon: Double, name: String, app: Bool) -> URL? {
        let ll = String(format: "%.6f,%.6f", lat, lon)
        var c: URLComponents
        switch self {
        case .cfmoto:
            return nil
        case .appleMaps:
            c = URLComponents(string: "https://maps.apple.com/")!
            c.queryItems = [URLQueryItem(name: "daddr", value: ll), URLQueryItem(name: "dirflg", value: "d"),
                            URLQueryItem(name: "q", value: name)]
        case .googleMaps:
            if app {
                c = URLComponents(string: "comgooglemaps://")!
                c.queryItems = [URLQueryItem(name: "daddr", value: ll), URLQueryItem(name: "directionsmode", value: "driving")]
            } else {
                c = URLComponents(string: "https://www.google.com/maps/dir/")!
                c.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: ll),
                                URLQueryItem(name: "travelmode", value: "driving")]
            }
        case .waze:
            c = URLComponents(string: app ? "waze://ul" : "https://waze.com/ul")!
            c.queryItems = [URLQueryItem(name: "ll", value: ll), URLQueryItem(name: "navigate", value: "yes"),
                            URLQueryItem(name: "utm_source", value: "io.github.cfmotolink.app")]
        }
        return c.url
    }
}

/// Guía activa en otra app: la moto muestra el mapa, la posición y el destino, sin giros.
struct ExternalGuide: Equatable {
    var provider: NavProviderID
    var destination: GeoPoint
    var name: String
}

enum DashTheme: String, Codable, CaseIterable, Identifiable {
    /// Claro de día y oscuro de noche, según el amanecer y el atardecer donde estás.
    case auto, dark, light
    var id: String { rawValue }
    var title: String { self == .auto ? "Automático" : (self == .dark ? "Siempre oscuro" : "Siempre claro") }
    var short: String { self == .auto ? "Automático" : (self == .dark ? "Oscuro" : "Claro") }
}

struct DashLayout: Codable, Equatable {
    var template: DashTemplate = .overlay
    var slots: [DashModule?] = []
    /// Parte del ancho para la zona principal.
    var split: Double = 0.6
    /// Parte del alto para la zona lateral de arriba (solo en "Principal + 2").
    var sideSplit: Double = 0.46
    /// Zona principal a la derecha.
    var mirrored = false
    /// Tarjetas sobre el mapa (solo en "Mapa completo").
    var overlay = OverlaySettings()

    static let splitRange = 0.4...0.75
    static let sideRange = 0.3...0.7

    static func preset(_ mode: DashMode) -> DashLayout {
        switch mode {
        case .gps: return .overlay(OverlaySettings(music: false, notices: false))
        case .gpsMusic: return .overlay(OverlaySettings(music: true, notices: false))
        case .split: return DashLayout(template: .columns, slots: [.nav, .music], split: 0.58)
        case .music: return DashLayout(template: .full, slots: [.music])
        case .full, .custom: return .overlay(OverlaySettings(music: true, notices: true))
        case .gpsNotices: return .overlay(OverlaySettings(music: false, notices: true))
        case .musicNotices: return DashLayout(template: .columns, slots: [.music, .notices], split: 0.58)
        }
    }

    static func overlay(_ o: OverlaySettings) -> DashLayout {
        var l = DashLayout()
        l.template = .overlay
        l.slots = []
        l.overlay = o
        return l
    }

    /// Deja el diseño en un estado válido: zonas justas, sin módulos repetidos y tamaños dentro de rango.
    mutating func normalize() {
        var seen = Set<DashModule>()
        var out: [DashModule?] = []
        for i in 0..<template.slotCount {
            let m = i < slots.count ? slots[i] : nil
            if let m = m, !seen.contains(m) {
                seen.insert(m)
                out.append(m)
            } else {
                out.append(nil)
            }
        }
        slots = out
        split = min(max(split, DashLayout.splitRange.lowerBound), DashLayout.splitRange.upperBound)
        sideSplit = min(max(sideSplit, DashLayout.sideRange.lowerBound), DashLayout.sideRange.upperBound)
    }

    var normalized: DashLayout {
        var c = self
        c.normalize()
        return c
    }

    var showsRoute: Bool { template == .overlay || slots.contains { $0?.showsRoute == true } }
    var showsMusic: Bool { template == .overlay ? overlay.music : slots.contains { $0 == .music } }
    /// Hay un mapa en la imagen (para pedir el de calles solo cuando hace falta).
    var showsMap: Bool { template == .overlay || slots.contains { $0 == .nav || $0 == .map } }

    /// Cambia de plantilla y rellena las zonas nuevas con módulos que aún no se muestran.
    mutating func setTemplate(_ t: DashTemplate) {
        template = t
        normalize()
        let order: [DashModule] = [.nav, .music, .notices, .trip, .turn, .map, .clock]
        for i in slots.indices where slots[i] == nil {
            if let m = order.first(where: { !slots.contains($0) }) { slots[i] = m }
        }
    }

    mutating func swapSlots(_ a: Int, _ b: Int) {
        normalize()
        guard a != b, slots.indices.contains(a), slots.indices.contains(b) else { return }
        slots.swapAt(a, b)
    }

    /// Pone un módulo en una zona. Si ya estaba en otra, las intercambia.
    mutating func place(_ module: DashModule?, at slot: Int) {
        normalize()
        guard slots.indices.contains(slot) else { return }
        if let m = module, let other = slots.firstIndex(of: m), other != slot {
            slots[other] = slots[slot]
        }
        slots[slot] = module
    }
}

extension DashLayout {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DashLayout()
        template = (try? c.decode(DashTemplate.self, forKey: .template)) ?? d.template
        slots = (try? c.decode([DashModule?].self, forKey: .slots)) ?? d.slots
        split = (try? c.decode(Double.self, forKey: .split)) ?? d.split
        sideSplit = (try? c.decode(Double.self, forKey: .sideSplit)) ?? d.sideSplit
        mirrored = (try? c.decode(Bool.self, forKey: .mirrored)) ?? d.mirrored
        overlay = (try? c.decode(OverlaySettings.self, forKey: .overlay)) ?? d.overlay
    }
}

struct DashProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var layout: DashLayout
    var theme: DashTheme = .auto
}

struct DashRules: Codable, Equatable {
    var navStartsGpsMusic = true
    var navEndRestores = true
    var musicOnlyWithoutRoute = false
    var turnPriority = true
}

struct DashConfig: Codable, Equatable {
    /// 3: versión 0.6 (día y noche automáticos). 2: 0.5. Sin número: 0.4.
    var version = 3
    var mode: DashMode = .gpsMusic
    var custom = DashLayout.preset(.custom)
    var theme: DashTheme = .auto
    var rules = DashRules()
    var profiles: [DashProfile] = DashConfig.defaultProfiles
    var activeProfile: UUID?
    var noticeSeconds: Double = 8
    var noticePrivacy = false
    var noticeNav = true
    var noticeLink = true
    var noticeBattery = true
    var showArtwork = true
    var showProgress = true
    var map = MapSettings()
    var musicProvider: MusicProvider = .appleMusic
    /// Client ID de la app que el usuario registra en developer.spotify.com (no es secreto).
    var spotifyClientID = ""
    var navProvider: NavProviderID = .cfmoto
    var musicStyle: MusicCardStyle = .dynamic
    /// Fuerza de los colores de la portada (0…1).
    var musicIntensity: Double = 0.75
    var artworkSize: ArtworkSize = .normal
    var showArtist = true
    var showSource = true
    /// Transiciones suaves (colores, mapa, ruta nueva).
    var animations = true

    var layout: DashLayout { (mode == .custom ? custom : DashLayout.preset(mode)).normalized }

    init() {}

    static var defaultProfiles: [DashProfile] {
        var trip = OverlaySettings(music: false, notices: false, clock: true)
        trip.maneuverSize = .large
        var city = OverlaySettings(music: true, notices: true)
        city.maneuverSize = .large
        var big = OverlaySettings(music: true, notices: false)
        big.musicSize = .large
        return [
            DashProfile(name: "Navegación diaria", layout: .preset(.gpsMusic)),
            DashProfile(name: "Viaje largo", layout: .overlay(trip)),
            DashProfile(name: "Música", layout: .overlay(big)),
            DashProfile(name: "Ciudad", layout: .overlay(city)),
            DashProfile(name: "Personalizado 1", layout: DashLayout(template: .columns, slots: [.nav, .music], split: 0.64)),
            DashProfile(name: "Personalizado 2", layout: DashLayout(template: .mainSide, slots: [.map, .turn, .trip], split: 0.5, sideSplit: 0.55, mirrored: true)),
        ]
    }

    /// Diseños de los perfiles que traía la 0.4, para reconocerlos al actualizar.
    static let legacyProfileLayouts: [DashLayout] = [
        DashLayout(template: .columns, slots: [.nav, .music], split: 0.64),
        DashLayout(template: .mainSide, slots: [.nav, .trip, .music], split: 0.62, sideSplit: 0.42),
        DashLayout(template: .columns, slots: [.music, .notices], split: 0.58),
        DashLayout(template: .mainSide, slots: [.nav, .music, .notices]),
        DashLayout(template: .columns, slots: [.turn, .map], split: 0.55),
        DashLayout(template: .mainSide, slots: [.map, .turn, .trip], split: 0.5, sideSplit: 0.55, mirrored: true),
    ]

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(_ data: Data) -> DashConfig? {
        guard var c = try? JSONDecoder().decode(DashConfig.self, from: data) else { return nil }
        c.migrate()
        return c
    }

    /// Pasa una configuración vieja al formato actual sin perder lo que el usuario creó.
    mutating func migrate() {
        if version < 3 {
            // Hasta la 0.5 el tema venía fijo en oscuro (por eso el mapa nunca era claro). Si
            // seguía así, pasa a automático; si el usuario eligió claro, se respeta.
            if theme == .dark { theme = .auto }
            for i in profiles.indices where profiles[i].theme == .dark { profiles[i].theme = .auto }
        }
        guard version < 2 else {
            version = 3
            return
        }
        version = 3
        // Los perfiles de fábrica que siguen igual se cambian por los nuevos; los creados o
        // editados por el usuario se conservan.
        let fresh = DashConfig.defaultProfiles
        for i in profiles.indices {
            if let j = DashConfig.legacyProfileLayouts.firstIndex(of: profiles[i].layout.normalized), j < fresh.count,
               profiles[i].name == fresh[j].name {
                profiles[i].layout = fresh[j].layout
            }
        }
    }
}

extension DashConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DashConfig()
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        mode = (try? c.decode(DashMode.self, forKey: .mode)) ?? d.mode
        custom = (try? c.decode(DashLayout.self, forKey: .custom)) ?? d.custom
        theme = (try? c.decode(DashTheme.self, forKey: .theme)) ?? d.theme
        rules = (try? c.decode(DashRules.self, forKey: .rules)) ?? d.rules
        profiles = (try? c.decode([DashProfile].self, forKey: .profiles)) ?? d.profiles
        activeProfile = try? c.decode(UUID.self, forKey: .activeProfile)
        noticeSeconds = (try? c.decode(Double.self, forKey: .noticeSeconds)) ?? d.noticeSeconds
        noticePrivacy = (try? c.decode(Bool.self, forKey: .noticePrivacy)) ?? d.noticePrivacy
        noticeNav = (try? c.decode(Bool.self, forKey: .noticeNav)) ?? d.noticeNav
        noticeLink = (try? c.decode(Bool.self, forKey: .noticeLink)) ?? d.noticeLink
        noticeBattery = (try? c.decode(Bool.self, forKey: .noticeBattery)) ?? d.noticeBattery
        showArtwork = (try? c.decode(Bool.self, forKey: .showArtwork)) ?? d.showArtwork
        showProgress = (try? c.decode(Bool.self, forKey: .showProgress)) ?? d.showProgress
        map = (try? c.decode(MapSettings.self, forKey: .map)) ?? d.map
        musicProvider = (try? c.decode(MusicProvider.self, forKey: .musicProvider)) ?? d.musicProvider
        spotifyClientID = (try? c.decode(String.self, forKey: .spotifyClientID)) ?? d.spotifyClientID
        navProvider = (try? c.decode(NavProviderID.self, forKey: .navProvider)) ?? d.navProvider
        musicStyle = (try? c.decode(MusicCardStyle.self, forKey: .musicStyle)) ?? d.musicStyle
        musicIntensity = min(1, max(0, (try? c.decode(Double.self, forKey: .musicIntensity)) ?? d.musicIntensity))
        artworkSize = (try? c.decode(ArtworkSize.self, forKey: .artworkSize)) ?? d.artworkSize
        showArtist = (try? c.decode(Bool.self, forKey: .showArtist)) ?? d.showArtist
        showSource = (try? c.decode(Bool.self, forKey: .showSource)) ?? d.showSource
        animations = (try? c.decode(Bool.self, forKey: .animations)) ?? d.animations
    }
}

// MARK: - Distribución

struct DashFrame: Equatable {
    let slot: Int
    let module: DashModule
    let rect: CGRect
}

/// Calcula dónde va cada zona dentro del área útil. Por construcción las zonas no se solapan
/// ni se salen del área.
enum DashLayoutEngine {
    /// Área de la imagen que la moto no tapa con sus indicadores.
    static func usableArea(width: CGFloat, height: CGFloat, reservedBottom: CGFloat) -> CGRect {
        let r = max(0, min(0.4, reservedBottom))
        return CGRect(x: 0, y: 0, width: width, height: (height * (1 - r)).rounded())
    }

    /// Rectángulo de cada zona de la plantilla (aunque esté vacía).
    static func slotRects(_ layout: DashLayout, in area: CGRect, gap: CGFloat) -> [CGRect] {
        let l = layout.normalized
        switch l.template {
        case .overlay:
            return []
        case .full:
            return [area]
        case .columns, .mainSide:
            let mainW = ((area.width - gap) * CGFloat(l.split)).rounded()
            let sideW = area.width - gap - mainW
            let mainX = l.mirrored ? area.minX + sideW + gap : area.minX
            let sideX = l.mirrored ? area.minX : area.minX + mainW + gap
            let main = CGRect(x: mainX, y: area.minY, width: mainW, height: area.height)
            if l.template == .columns {
                return [main, CGRect(x: sideX, y: area.minY, width: sideW, height: area.height)]
            }
            let topH = ((area.height - gap) * CGFloat(l.sideSplit)).rounded()
            return [
                main,
                CGRect(x: sideX, y: area.minY, width: sideW, height: topH),
                CGRect(x: sideX, y: area.minY + topH + gap, width: sideW, height: area.height - gap - topH),
            ]
        }
    }

    /// Zonas con módulo. Una zona vacía cede su espacio a la vecina.
    static func frames(_ layout: DashLayout, in area: CGRect, gap: CGFloat) -> [DashFrame] {
        let l = layout.normalized
        let rects = slotRects(l, in: area, gap: gap)
        var out: [DashFrame] = []
        func add(_ slot: Int, _ rect: CGRect) {
            if let m = l.slots[slot] { out.append(DashFrame(slot: slot, module: m, rect: rect)) }
        }
        switch l.template {
        case .overlay:
            return []
        case .full:
            add(0, rects[0])
        case .columns:
            if l.slots[0] == nil { add(1, area) } else if l.slots[1] == nil { add(0, area) } else {
                add(0, rects[0])
                add(1, rects[1])
            }
        case .mainSide:
            let side = rects[1].union(rects[2])
            let sideEmpty = l.slots[1] == nil && l.slots[2] == nil
            if l.slots[0] == nil {
                let whole = sideEmpty ? area : area
                if l.slots[1] != nil && l.slots[2] != nil {
                    let topH = ((whole.height - gap) * CGFloat(l.sideSplit)).rounded()
                    add(1, CGRect(x: whole.minX, y: whole.minY, width: whole.width, height: topH))
                    add(2, CGRect(x: whole.minX, y: whole.minY + topH + gap, width: whole.width, height: whole.height - gap - topH))
                } else {
                    add(1, whole)
                    add(2, whole)
                }
            } else if sideEmpty {
                add(0, area)
            } else {
                add(0, rects[0])
                if l.slots[2] == nil { add(1, side) } else if l.slots[1] == nil { add(2, side) } else {
                    add(1, rects[1])
                    add(2, rects[2])
                }
            }
        }
        return out
    }
}

extension DashLayoutEngine {
    /// Dónde se dibuja el mapa (para pedir la imagen de calles del tamaño justo).
    static func mapRect(_ layout: DashLayout, width: CGFloat, height: CGFloat, reservedBottom: CGFloat) -> CGRect? {
        let l = layout.normalized
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        if l.template == .overlay { return usableArea(width: width, height: height, reservedBottom: reservedBottom) }
        guard l.showsMap else { return nil }
        let k = width / 800
        let gap = (6 * k).rounded()
        let area = usableArea(width: width, height: height, reservedBottom: reservedBottom).insetBy(dx: gap, dy: gap)
        let fs = frames(l, in: area, gap: gap)
        return (fs.first { $0.module == .nav } ?? fs.first { $0.module == .map })?.rect ?? full
    }

    /// Tamaño base de cada tarjeta (en la escala de una imagen de 800 de ancho).
    static func cardSize(_ item: OverlayItem, _ o: OverlaySettings) -> CGSize {
        switch item {
        // 0.6.2: la maniobra compacta, un 30 % más pequeña por lado (era 284×136) para ver la
        // ruta; lleva flecha, distancia y calle. La grande sigue igual para quien la prefiera.
        case .maneuver: return o.maneuverSize == .large ? CGSize(width: 340, height: 176) : CGSize(width: 200, height: 96)
        case .music: return o.musicSize == .large ? CGSize(width: 300, height: 124) : CGSize(width: 250, height: 84)
        case .trip: return CGSize(width: 400, height: 46)
        case .notices: return CGSize(width: 262, height: 58)
        case .clock: return CGSize(width: 136, height: 46)
        case .compass: return CGSize(width: 44, height: 44)
        case .time: return CGSize(width: 116, height: 30)
        }
    }

    /// Hora actual: siempre en el mismo sitio (arriba a la derecha), en todos los modos y con o
    /// sin ruta. `area`: el área útil de la imagen.
    static func statusClock(in area: CGRect, k: CGFloat) -> CGRect {
        let size = cardSize(.time, OverlaySettings())
        let margin = 12 * k
        return CGRect(x: area.maxX - margin - size.width * k, y: area.minY + margin,
                      width: size.width * k, height: size.height * k)
    }

    /// Tarjetas flotantes sobre el mapa. Las que comparten esquina se apilan; ninguna se sale
    /// del área ni se monta sobre otra (si no caben, se descartan las menos importantes).
    static func overlayCards(_ o: OverlaySettings, in area: CGRect, k: CGFloat, showNotices: Bool = true) -> [OverlayCard] {
        let margin = 12 * k
        let gap = 8 * k
        let inner = area.insetBy(dx: margin, dy: margin)
        // Orden de prioridad: lo que más importa para conducir va primero.
        var wanted: [(OverlayItem, CardSpot)] = []
        if o.maneuver { wanted.append((.maneuver, o.maneuverSpot)) }
        if o.trip { wanted.append((.trip, o.tripSpot)) }
        if o.music { wanted.append((.music, o.musicSpot)) }
        if o.notices && showNotices { wanted.append((.notices, o.noticesSpot)) }
        if o.clock { wanted.append((.clock, o.clockSpot)) }

        var placed: [OverlayCard] = []
        var stackTop: [CardSpot: CGFloat] = [:]
        var stackBottom: [CardSpot: CGFloat] = [:]
        // La hora va primero y no se mueve: lo que vaya arriba a la derecha se pone debajo.
        let clock = statusClock(in: area, k: k)
        placed.append(OverlayCard(item: .time, rect: clock))
        stackTop[.topRight] = clock.maxY + gap

        func attempt(_ item: OverlayItem, _ spot: CardSpot) -> CGRect? {
            var size = cardSize(item, o)
            size = CGSize(width: min(size.width * k, inner.width), height: min(size.height * k, inner.height))
            var rect: CGRect
            switch spot {
            case .topLeft, .topRight:
                let y = stackTop[spot] ?? inner.minY
                let x = spot == .topLeft ? inner.minX : inner.maxX - size.width
                rect = CGRect(x: x, y: y, width: size.width, height: size.height)
            case .bottomLeft, .bottomRight, .bottomCenter:
                let bottom = stackBottom[spot] ?? inner.maxY
                let x: CGFloat
                switch spot {
                case .bottomLeft: x = inner.minX
                case .bottomRight: x = inner.maxX - size.width
                default: x = inner.midX - size.width / 2
                }
                rect = CGRect(x: x, y: bottom - size.height, width: size.width, height: size.height)
            }
            // La barra del centro se estrecha entre las esquinas de abajo si hace falta.
            if spot == .bottomCenter {
                var left = inner.minX
                var right = inner.maxX
                for s in placed where s.rect.maxY > rect.minY && s.rect.minY < rect.maxY {
                    if s.rect.midX < inner.midX { left = max(left, s.rect.maxX + gap) } else { right = min(right, s.rect.minX - gap) }
                }
                if rect.minX < left || rect.maxX > right {
                    let w = min(size.width, right - left)
                    if w >= 240 * k {
                        rect = CGRect(x: max(left, min(inner.midX - w / 2, right - w)), y: rect.minY, width: w, height: rect.height)
                    }
                }
            }
            // Si choca con otra, se intenta justo debajo (arriba) o encima (abajo) de ella.
            var tries = 0
            while let hit = placed.first(where: { $0.rect.intersects(rect.insetBy(dx: -gap / 2, dy: -gap / 2)) }), tries < 8 {
                if spot.isTop {
                    rect.origin.y = hit.rect.maxY + gap
                } else {
                    rect.origin.y = hit.rect.minY - gap - rect.height
                }
                tries += 1
            }
            let fits = rect.minX >= inner.minX - 0.5 && rect.maxX <= inner.maxX + 0.5
                && rect.minY >= inner.minY - 0.5 && rect.maxY <= inner.maxY + 0.5
            guard fits, !placed.contains(where: { $0.rect.intersects(rect) }) else { return nil }
            return rect
        }

        func commit(_ item: OverlayItem, _ spot: CardSpot, _ rect: CGRect) {
            placed.append(OverlayCard(item: item, rect: rect))
            if spot.isTop {
                stackTop[spot] = rect.maxY + gap
            } else {
                stackBottom[spot] = rect.minY - gap
            }
        }

        for (item, spot) in wanted {
            if let rect = attempt(item, spot) { commit(item, spot, rect) }
        }
        // La brújula, pequeña, en la primera esquina que tenga sitio.
        let used = Set(placed.filter { $0.item != .time }.map { o.spot($0.item) })
        var candidates: [CardSpot] = used.contains(.bottomRight) && !used.contains(.bottomLeft)
            ? [.bottomLeft, .bottomRight] : [.bottomRight, .bottomLeft]
        candidates += [.topRight, .topLeft, .bottomCenter]
        for spot in candidates {
            if let rect = attempt(.compass, spot) {
                commit(.compass, spot, rect)
                break
            }
        }
        return placed
    }
}

// MARK: - Datos que se dibujan

struct MusicSnapshot {
    var available = false
    var source = ""
    var title = ""
    var artist = ""
    /// Álbum (si el servicio lo da).
    var album = ""
    var playing = false
    var duration: Double = 0
    var position: Double = 0
    /// Momento en que se leyó `position` (segundos desde la fecha de referencia).
    var positionTime: TimeInterval = 0
    var artwork: CGImage?
    /// Colores dominantes de la portada (si hay portada).
    var palette: ArtPalette?
}

/// Fundido al cambiar de canción: la anterior se desvanece mientras entra la nueva. Lógica pura
/// (la usa el estado del panel y la comprueban las pruebas). Sin coste apreciable: dura
/// menos de medio segundo y solo mezcla lo que ya se dibuja.
struct TrackTransition {
    static let duration = 0.45
    private(set) var from: MusicSnapshot?
    private(set) var changed: TimeInterval = -1_000_000
    private(set) var artFrom: CGImage?
    private(set) var artChanged: TimeInterval = -1_000_000

    /// Lo que identifica una canción (sin música: vacío).
    static func key(_ m: MusicSnapshot) -> String {
        m.available && !m.title.isEmpty ? m.source + "\u{1}" + m.title + "\u{1}" + m.artist : ""
    }

    /// Sonaba `old` y llega `new` en el momento `t` (segundos).
    mutating func update(old: MusicSnapshot, new: MusicSnapshot, at t: TimeInterval) {
        if TrackTransition.key(old) != TrackTransition.key(new) {
            from = old
            changed = t
            artFrom = nil
            artChanged = -1_000_000
        } else if old.artwork !== new.artwork {
            // Misma canción, portada nueva (Spotify la entrega después del título).
            artFrom = old.artwork
            artChanged = t
        }
    }

    /// Avance (0…1) del fundido de canción, o nil si no hay ninguno en curso.
    func fade(at t: TimeInterval) -> Double? {
        let f = (t - changed) / TrackTransition.duration
        return f >= 0 && f < 1 ? f : nil
    }

    /// Avance del fundido de la portada de la misma canción, o nil.
    func artFade(at t: TimeInterval) -> Double? {
        let f = (t - artChanged) / TrackTransition.duration
        return f >= 0 && f < 1 ? f : nil
    }
}

/// Pantalla de música completa (modo «4 · Música»), al estilo de CarPlay: portada grande a la
/// derecha; título, artista y estado centrados a la izquierda; barra de progreso a todo el
/// ancho con el tiempo transcurrido y la duración. Función pura para poder probarla.
struct MusicStageLayout: Equatable {
    var header: CGRect
    var artwork: CGRect
    var text: CGRect
    var progress: CGRect

    /// ¿Cabe esta distribución? Si no (columna estrecha), se usa la tarjeta de siempre.
    static func fits(_ r: CGRect, k: CGFloat) -> Bool { r.width >= 520 * k && r.height >= 220 * k }

    /// `reserve`: la hora actual, si cae dentro de la zona (la cabecera la deja libre y la
    /// portada empieza debajo).
    static func make(_ r: CGRect, k: CGFloat, artwork: Bool, size: ArtworkSize, reserve: CGRect?) -> MusicStageLayout {
        let pad = 26 * k
        var header = CGRect(x: r.minX + pad, y: r.minY + 14 * k, width: r.width - 2 * pad, height: 26 * k)
        let clock = reserve.flatMap { $0.intersects(r) ? $0 : nil }
        if let c = clock, c.intersects(header.insetBy(dx: 0, dy: -8 * k)) {
            header.size.width = max(0, c.minX - 12 * k - header.minX)
        }
        let progressH = 28 * k
        let progress = CGRect(x: r.minX + pad, y: r.maxY - 18 * k - progressH, width: r.width - 2 * pad, height: progressH)
        // La portada usa todo el alto libre de la derecha: de la hora (o del borde) a la barra.
        var artTop = r.minY + 16 * k
        if let c = clock { artTop = max(artTop, c.maxY + 6 * k) }
        let artH = max(0, progress.minY - 12 * k - artTop)
        var art = CGRect.zero
        var textRight = r.maxX - pad
        if artwork {
            let f: CGFloat = size == .small ? 0.8 : (size == .large ? 1 : 0.95)
            let side = (min(artH, r.width * 0.37) * f).rounded()
            art = CGRect(x: r.maxX - pad - side, y: (artTop + (artH - side) / 2).rounded(), width: side, height: side)
            textRight = art.minX - 30 * k
        }
        let textTop = header.maxY + 10 * k
        let text = CGRect(x: r.minX + pad, y: textTop, width: max(0, textRight - r.minX - pad),
                          height: max(0, progress.minY - 12 * k - textTop))
        return MusicStageLayout(header: header, artwork: art, text: text, progress: progress)
    }
}

/// 0.6.3: un solo reproductor para todos los modos. Las tres formas comparten el fondo
/// (degradado con los colores de la portada y un resplandor detrás de ella), la portada con
/// sombra, la letra (título en negrita, artista, álbum) y la barra de progreso:
///  - `stage`: zona ancha (Música sola). Portada grande a la derecha y textos centrados.
///  - `column`: zona alta y estrecha (Dividida, Música + Avisos). Portada arriba, textos debajo.
///  - `row`: tarjetas y zonas bajas (Nav + Música, Completo). Portada a la izquierda.
/// 0.6.4: todas llevan los botones de la referencia (anterior, reproducir/pausar y siguiente)
/// donde antes iba el estado («Reproduciendo»). Son solo dibujo: la pantalla de la moto no es
/// táctil para la app y el protocolo no envía teclas, así que la música se sigue controlando
/// desde el iPhone o el intercomunicador. El botón central muestra el estado real.
enum MusicPlayerStyle: String {
    case stage, column, row
}

struct MusicPlayerLayout: Equatable {
    var style: MusicPlayerStyle
    /// Nombre del servicio (en `row` va en la primera línea de los textos y esto queda vacío).
    var header: CGRect
    var artwork: CGRect
    /// Título, artista y álbum.
    var text: CGRect
    /// Fila de la barra (con los tiempos a los lados si `times`).
    var progress: CGRect
    var times: Bool
    /// Tamaños de letra (ya multiplicados por la escala de la imagen).
    var title: CGFloat
    var artist: CGFloat
    /// 0: sin línea de álbum.
    var album: CGFloat
    var source: CGFloat
    var time: CGFloat
    /// Grosor de la barra de progreso.
    var bar: CGFloat
    /// Textos centrados (stage, column) o alineados a la izquierda (row).
    var centered: Bool
    /// Tarjeta flotante sobre el mapa (esquinas redondeadas y algo de transparencia).
    var card: Bool
    /// 0.6.4: fila de los botones y diámetro del botón central (0: sin botones).
    var controls: CGRect
    var button: CGFloat
    /// Botones centrados en su fila (música completa y columna) o desde la izquierda (filas).
    var controlsCentered: Bool
    /// Tarjeta compacta: el nombre del servicio va en la fila de los botones, a la derecha.
    var sourceInControls: Bool

    /// Portada mínima para usar la forma en columna; si sale más pequeña, se usa la fila.
    static let minColumnArtwork: CGFloat = 140

    /// Los tres botones dentro de su fila.
    var transport: TransportGeometry {
        TransportGeometry.make(controls, button: button, centered: controlsCentered)
    }

    /// `card`: tamaño de la tarjeta sobre el mapa, o nil si es una zona del panel.
    /// `reserve`: la hora actual, si cae dentro (se deja libre).
    static func make(_ r: CGRect, k: CGFloat, artwork: Bool, size: ArtworkSize, reserve: CGRect?,
                     card: CardSize? = nil) -> MusicPlayerLayout {
        let clock = reserve.flatMap { $0.intersects(r) ? $0 : nil }
        if card == nil && MusicStageLayout.fits(r, k: k) {
            let L = MusicStageLayout.make(r, k: k, artwork: artwork, size: size, reserve: clock)
            // Los botones van al pie de la columna de los textos, donde estaba el estado, y los
            // textos se centran en lo que queda encima (como en CarPlay).
            let button = (62 * k).rounded()
            let controls = CGRect(x: L.text.minX, y: (L.text.maxY - button).rounded(), width: L.text.width, height: button)
            var text = L.text
            text.size.height = max(0, controls.minY - 16 * k - text.minY)
            return MusicPlayerLayout(style: .stage, header: L.header, artwork: L.artwork, text: text, progress: L.progress,
                                     times: true, title: 40 * k, artist: 25 * k, album: 19 * k, source: 15 * k,
                                     time: 18 * k, bar: 6 * k, centered: true, card: false,
                                     controls: controls, button: button, controlsCentered: true, sourceInControls: false)
        }
        if card == nil && r.width >= 240 * k && r.height >= 300 * k, let c = column(r, k: k, artwork: artwork, size: size, clock: clock) {
            return c
        }
        return row(r, k: k, artwork: artwork, size: size, clock: clock, card: card)
    }

    /// Alto aproximado de una línea de texto (ascendente + descendente de la letra del sistema).
    static func lineHeight(_ size: CGFloat) -> CGFloat { size * 1.2 }

    private static func factor(_ size: ArtworkSize) -> CGFloat { size == .small ? 0.8 : (size == .large ? 1 : 0.95) }

    private static func column(_ r: CGRect, k: CGFloat, artwork: Bool, size: ArtworkSize, clock: CGRect?) -> MusicPlayerLayout? {
        let padX = max(16 * k, min(24 * k, r.width * 0.06))
        var header = CGRect(x: r.minX + padX, y: r.minY + 14 * k, width: r.width - 2 * padX, height: 22 * k)
        if let c = clock, c.intersects(header.insetBy(dx: 0, dy: -8 * k)) {
            header.size.width = max(0, c.minX - 12 * k - header.minX)
        }
        let progressH = 22 * k
        let progress = CGRect(x: r.minX + padX, y: r.maxY - 14 * k - progressH, width: r.width - 2 * padX, height: progressH)
        // 0.6.4: los botones, encima de la barra (en el sitio del estado).
        let button = (44 * k).rounded()
        let controls = CGRect(x: r.minX + padX, y: (progress.minY - 10 * k - button).rounded(), width: r.width - 2 * padX, height: button)
        let title = max(22 * k, min(28 * k, r.width * 0.075))
        let artist = title * 0.74
        // Título y artista (el álbum solo cabe en la música completa). Mismos espacios que usa el
        // dibujo.
        let block = lineHeight(title) + 8 * k + lineHeight(artist)
        var top = header.maxY + 10 * k
        if let c = clock { top = max(top, c.maxY + 6 * k) }
        var art = CGRect.zero
        var textTop = top
        if artwork {
            let room = controls.minY - 12 * k - block - 10 * k - top
            let side = (min(r.width - 2 * padX, room) * factor(size)).rounded()
            guard side >= minColumnArtwork * k else { return nil }
            // La portada y los textos, juntos y centrados en el alto libre.
            let used = side + 10 * k + block
            let y = (top + max(0, (controls.minY - 12 * k - top - used) / 2)).rounded()
            art = CGRect(x: (r.midX - side / 2).rounded(), y: y, width: side, height: side)
            textTop = art.maxY + 10 * k
        }
        let text = CGRect(x: r.minX + padX, y: textTop, width: r.width - 2 * padX, height: max(0, controls.minY - 8 * k - textTop))
        return MusicPlayerLayout(style: .column, header: header, artwork: art, text: text, progress: progress, times: true,
                                 title: title, artist: artist, album: 0, source: 13 * k, time: 14 * k,
                                 bar: 5 * k, centered: true, card: false,
                                 controls: controls, button: button, controlsCentered: true, sourceInControls: false)
    }

    private static func row(_ r: CGRect, k: CGFloat, artwork: Bool, size: ArtworkSize, clock: CGRect?, card: CardSize?) -> MusicPlayerLayout {
        let compactCard = card != nil && r.height < 100 * k
        let pad = card != nil ? (compactCard ? 10 * k : 12 * k) : max(12 * k, min(18 * k, r.height * 0.07))
        var content = r
        if let c = clock {
            // La hora cae en la zona: todo el contenido va por debajo.
            let top = c.maxY + 6 * k - pad
            if top > content.minY { content = CGRect(x: r.minX, y: top, width: r.width, height: max(0, r.maxY - top)) }
        }
        var side: CGFloat = 0
        var art = CGRect.zero
        var tx = r.minX + pad
        if artwork {
            side = min(content.height - 2 * pad, r.width * 0.42)
            if card == nil { side *= factor(size) }
            side = max(0, side.rounded())
            art = CGRect(x: r.minX + pad, y: (content.minY + pad + (content.height - 2 * pad - side) / 2).rounded(), width: side, height: side)
            tx = art.maxX + (card != nil ? 12 * k : max(14 * k, side * 0.09))
        }
        let tw = max(0, r.maxX - pad - tx)
        let inner = CGRect(x: tx, y: artwork ? art.minY : content.minY + pad, width: tw,
                           height: artwork ? side : content.height - 2 * pad)
        if compactCard {
            // 0.6.4, tarjeta compacta (250×84): título y artista; debajo, los botones con el
            // nombre del servicio a la derecha; la barra, fina, al pie.
            let bar = 3 * k
            let button = (22 * k).rounded()
            let progress = CGRect(x: tx, y: r.maxY - 4.5 * k - bar, width: tw, height: bar)
            let controls = CGRect(x: tx, y: (progress.minY - 5 * k - button).rounded(), width: tw, height: button)
            let text = CGRect(x: tx, y: inner.minY, width: tw, height: max(0, controls.minY - 3.5 * k - inner.minY))
            return MusicPlayerLayout(style: .row, header: .zero, artwork: art, text: text, progress: progress, times: false,
                                     title: 16 * k, artist: 12.5 * k, album: 0, source: 10.5 * k, time: 11 * k,
                                     bar: bar, centered: false, card: true,
                                     controls: controls, button: button, controlsCentered: false, sourceInControls: true)
        }
        if card != nil {
            // 0.6.4, tarjeta grande (300×124): servicio, título y artista; los botones; la barra
            // con los tiempos a los lados.
            let time = 11 * k
            let bar = 4 * k
            let button = (26 * k).rounded()
            let progress = CGRect(x: tx, y: inner.maxY - lineHeight(time), width: tw, height: lineHeight(time))
            let controls = CGRect(x: tx, y: (progress.minY - 5 * k - button).rounded(), width: tw, height: button)
            let text = CGRect(x: tx, y: inner.minY, width: tw, height: max(0, controls.minY - 4 * k - inner.minY))
            return MusicPlayerLayout(style: .row, header: .zero, artwork: art, text: text, progress: progress, times: true,
                                     title: 17 * k, artist: 13.5 * k, album: 0, source: 11 * k, time: time,
                                     bar: bar, centered: false, card: true,
                                     controls: controls, button: button, controlsCentered: false, sourceInControls: false)
        }
        // Zonas bajas (Música + Avisos con ruta, zona lateral): como la tarjeta grande, a escala.
        let reference = artwork ? side : content.height - 2 * pad
        let title = max(15 * k, min(30 * k, reference * 0.29, tw * 0.13))
        let artist = title * 0.78
        let source = max(11 * k, title * 0.58)
        let time = max(11 * k, title * 0.55)
        let bar = max(3 * k, title * 0.17)
        let times = inner.height >= 96 * k
        let progressH = times ? lineHeight(time) : bar
        let progress = CGRect(x: tx, y: inner.maxY - progressH, width: tw, height: progressH)
        let button = max(24 * k, min(44 * k, inner.height * 0.22)).rounded()
        let controls = CGRect(x: tx, y: (progress.minY - 8 * k - button).rounded(), width: tw, height: button)
        // Álbum solo si sobra alto (zonas grandes).
        let album: CGFloat = inner.height >= 170 * k ? title * 0.6 : 0
        let text = CGRect(x: tx, y: inner.minY, width: tw, height: max(0, controls.minY - 6 * k - inner.minY))
        return MusicPlayerLayout(style: .row, header: .zero, artwork: art, text: text, progress: progress, times: times,
                                 title: title, artist: artist, album: album, source: source, time: time,
                                 bar: bar, centered: false, card: false,
                                 controls: controls, button: button, controlsCentered: false, sourceInControls: false)
    }
}

/// 0.6.4: los tres botones del reproductor dentro de su fila: anterior, el círculo de
/// reproducir/pausar y siguiente. Función pura (la usan el dibujo y las pruebas).
struct TransportGeometry: Equatable {
    var previous: CGRect
    var play: CGRect
    var next: CGRect

    var bounds: CGRect { previous.union(play).union(next) }

    static func make(_ row: CGRect, button d: CGFloat, centered: Bool) -> TransportGeometry {
        guard d > 0, !row.isEmpty else { return TransportGeometry(previous: .zero, play: .zero, next: .zero) }
        // Iconos laterales algo menores que la mitad del círculo y bien separados de él, como en
        // la referencia; con un mínimo para que se distingan en las tarjetas pequeñas.
        let gw = max(d * 0.42, min(11, d * 0.6))
        let gh = (gw * 0.9).rounded()
        let gap = max(d * 0.62, 9)
        let total = d + 2 * (gap + gw)
        let x0 = (centered ? row.midX - total / 2 : row.minX).rounded()
        let cy = row.midY
        let previous = CGRect(x: x0, y: (cy - gh / 2).rounded(), width: gw.rounded(), height: gh)
        let play = CGRect(x: (x0 + gw + gap).rounded(), y: (cy - d / 2).rounded(), width: d, height: d)
        let next = CGRect(x: (play.maxX + gap).rounded(), y: previous.minY, width: gw.rounded(), height: gh)
        return TransportGeometry(previous: previous, play: play, next: next)
    }
}

/// 0.6.3: la maniobra dentro de una zona con mapa (pantalla dividida y diseños por zonas). La
/// tarjeta es la misma que sobre el mapa completo (compacta 200×96 o grande), en la esquina que
/// se eligió en el iPhone, y la barra del viaje y la brújula van donde no estorban.
struct NavZoneLayout: Equatable {
    var card: CGRect
    var trip: CGRect
    var compass: CGRect

    /// `reserve`: la hora actual si cae en la zona. `trip`: hay barra del viaje (ruta en curso).
    static func make(_ zone: CGRect, _ o: OverlaySettings, k: CGFloat, reserve: CGRect?, trip: Bool) -> NavZoneLayout {
        let m = 9 * k
        let clock = reserve.flatMap { $0.intersects(zone) ? $0 : nil }
        let base = DashLayoutEngine.cardSize(.maneuver, o)
        let large = o.maneuverSize == .large
        // Proporcional al espacio: nunca más de la mitad del ancho (compacta) o del 70 % (grande).
        let limitW = zone.width * (large ? 0.7 : 0.5)
        var w = min(base.width * k, max(160 * k, limitW))
        w = min(w, zone.width - 2 * m)
        let h = min(base.height * k * (large ? 0.86 : 1), zone.height * (large ? 0.42 : 0.3))
        let spot = o.maneuverSpot
        let top = spot.isTop
        var x: CGFloat
        switch spot {
        case .topLeft, .bottomLeft: x = zone.minX + m
        case .topRight, .bottomRight: x = zone.maxX - m - w
        case .bottomCenter: x = zone.midX - w / 2
        }
        var y = top ? zone.minY + m : zone.maxY - m - h
        if let c = clock, top, c.intersects(CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -4 * k, dy: -4 * k)) {
            // La hora está en esa esquina: la tarjeta empieza debajo de ella.
            y = c.maxY + 6 * k
        }
        let card = CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())

        // Barra del viaje: en el borde contrario a la tarjeta. A la derecha, para que el logotipo
        // de Mapas de Apple (abajo a la izquierda) quede a la vista.
        var tripRect = CGRect.zero
        // 0.6.3: los tres bloques del viaje (Distancia, Restante, Llegada) de la referencia, con
        // su nombre debajo; como mucho 300 de ancho para tapar poco mapa.
        let tripH = 44 * k
        if trip {
            let left = zone.minX + m + (top ? 70 * k : 0)
            var right = zone.maxX - m
            var ty = top ? zone.maxY - m - tripH : zone.minY + m
            if !top, let c = clock, c.maxY > ty, c.minX < right { right = min(right, c.minX - 8 * k) }
            if !top && card.minY < ty + tripH + 6 * k { ty = min(ty, card.minY - 6 * k - tripH) }
            let tw = max(0, min(right - left, 300 * k))
            tripRect = CGRect(x: top ? right - tw : left, y: ty, width: tw, height: tripH)
        }

        // Brújula: abajo a la derecha si está libre; si no, arriba a la derecha (debajo de la
        // hora) o abajo a la izquierda.
        let cs = 40 * k
        var candidates: [CGRect] = []
        let bottomY = (top && trip ? tripRect.minY - 6 * k : zone.maxY - m) - cs
        candidates.append(CGRect(x: zone.maxX - m - cs, y: bottomY, width: cs, height: cs))
        candidates.append(CGRect(x: zone.maxX - m - cs, y: max(zone.minY + m, (clock?.maxY ?? 0) + 6 * k), width: cs, height: cs))
        if trip && !top {
            // Viaje arriba (tarjeta abajo): debajo de los datos del viaje.
            candidates.append(CGRect(x: zone.maxX - m - cs, y: max(tripRect.maxY, (clock?.maxY ?? 0)) + 6 * k, width: cs, height: cs))
        }
        candidates.append(CGRect(x: zone.minX + m, y: zone.maxY - m - cs - (trip && top ? tripH + 6 * k : 0), width: cs, height: cs))
        let busy = [card, tripRect, clock ?? .zero].filter { !$0.isEmpty }
        let compass = candidates.first { cand in zone.contains(cand) && !busy.contains { $0.intersects(cand.insetBy(dx: -3 * k, dy: -3 * k)) } }
            ?? candidates[0]
        return NavZoneLayout(card: card, trip: tripRect, compass: compass)
    }
}

enum NoticeKind: String, Codable {
    case nav, link, battery, test
}

struct NoticeSnapshot: Identifiable, Equatable {
    var id: Int
    var kind: NoticeKind
    var title: String
    var text: String
    var time: TimeInterval
}

struct DashSnapshot {
    var nav = HUDSnapshot()
    var music = MusicSnapshot()
    var notices: [NoticeSnapshot] = []
    var layout = DashLayout()
    var theme: DashTheme = .dark
    var privacy = false
    var showArtwork = true
    var showProgress = true
    /// Datos de demostración: se marca en la imagen. Nunca se envía a la moto.
    var demo = false
    /// Mapa de calles de Apple (si hay uno que sirva para la posición actual).
    var map: MapBase?
    var mapSettings = MapSettings()
    /// Mapa anterior mientras dura el fundido al cambiar de día a noche o de estilo.
    var mapFrom: MapBase?
    var mapFade: Double = 1
    /// Noche o día ya decidido (tema y sol); lo comparten el panel y el mapa.
    var night = true
    var musicStyle: MusicCardStyle = .dynamic
    var musicIntensity: Double = 0.75
    var artworkSize: ArtworkSize = .normal
    var showArtist = true
    var showSource = true
    /// Colores de la canción anterior y avance de la transición (0…1).
    var paletteFrom: ArtPalette?
    var paletteFade: Double = 1
    /// Canción anterior mientras dura el fundido al cambiar de canción (0…1).
    var musicFrom: MusicSnapshot?
    var musicFade: Double = 1
    /// Portada anterior de la misma canción (por ejemplo, la de Spotify que llega tarde).
    var artFrom: CGImage?
    var artFade: Double = 1
    /// 0.6.4: la música pasa de sonar a pausa (o al revés): avance del fundido del botón central (0…1).
    var playFade: Double = 1
    /// Ruta recién recalculada: avance del fundido de entrada (0…1).
    var routeFade: Double = 1
    /// Ruta guiada por otra app (la moto muestra solo el destino).
    var external: ExternalGuide?
    /// 0.6.3: cuánta ruta tiene mapa guardado (para avisar en la moto cuando se acaba).
    var mapCoverage = MapCoverageState.none
}

// MARK: - Reglas automáticas

struct DashAutoState: Codable, Equatable {
    var saved: DashMode?
    var turnSaved: DashMode?
}

enum DashEvent: Equatable {
    case navStarted, navEnded, musicStarted(routeActive: Bool), turnNear, turnPassed
}

/// Cambios de modo automáticos. Lógica pura: recibe un evento y ajusta la configuración.
enum DashRulesEngine {
    @discardableResult
    static func apply(_ event: DashEvent, config: inout DashConfig, auto: inout DashAutoState) -> Bool {
        let before = config.mode
        switch event {
        case .navStarted:
            if config.rules.navStartsGpsMusic && !config.layout.showsRoute {
                auto.saved = config.mode
                config.mode = .gpsMusic
            }
        case .navEnded:
            auto.turnSaved = nil
            if config.rules.navEndRestores, let saved = auto.saved {
                config.mode = saved
            }
            auto.saved = nil
        case .musicStarted(let routeActive):
            if config.rules.musicOnlyWithoutRoute && !routeActive && !config.layout.showsMusic {
                if auto.saved == nil { auto.saved = config.mode }
                config.mode = .music
            }
        case .turnNear:
            if config.rules.turnPriority && !config.layout.showsRoute {
                auto.turnSaved = config.mode
                config.mode = .gps
            }
        case .turnPassed:
            if let saved = auto.turnSaved {
                config.mode = saved
                auto.turnSaved = nil
            }
        }
        return config.mode != before
    }
}

// MARK: - Datos de demostración (solo para vistas previas y pruebas)

enum DashDemo {
    static func shape() -> HUDRouteShape {
        var points: [CGPoint] = []
        for i in 0...20 { points.append(CGPoint(x: 0, y: Double(i) * 20)) }
        for i in 1...18 { points.append(CGPoint(x: Double(i) * 20, y: 400)) }
        for i in 1...20 {
            let a = Double(i) / 20 * Double.pi / 3
            points.append(CGPoint(x: 360 + sin(a) * 300, y: 400 + (1 - cos(a)) * 300))
        }
        let last = points[points.count - 1]
        for i in 1...25 { points.append(CGPoint(x: Double(last.x) - Double(i) * 18, y: Double(last.y) + Double(i) * 14)) }
        return HUDRouteShape(points: points)
    }

    private static let route = shape()

    /// Portada de demostración dibujada aquí (degradado rojo y negro con un círculo claro), para
    /// ver los colores de la tarjeta de música sin depender de Spotify ni de Apple Music.
    static let artwork: CGImage? = {
        let side = 256
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: info) else { return nil }
        let colors = [CGColor(srgbRed: 0.78, green: 0.08, blue: 0.12, alpha: 1),
                      CGColor(srgbRed: 0.05, green: 0.02, blue: 0.03, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        }
        ctx.setFillColor(CGColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 150, y: 146, width: 70, height: 70))
        return ctx.makeImage()
    }()

    static let palette: ArtPalette? = artwork.flatMap { ArtPalette.extract($0) }

    static func nav(now: Date) -> HUDSnapshot {
        var s = HUDSnapshot()
        s.navigating = true
        s.gpsOk = true
        s.kind = .right
        s.distanceToManeuver = 350
        s.instruction = "Da vuelta a la derecha por 7a Avenida"
        s.thenKind = .left
        s.remainingDistance = 7400
        s.remainingTime = 18 * 60
        s.eta = now.addingTimeInterval(18 * 60)
        s.fraction = 0.34
        s.shape = route
        s.progress = 50
        s.maneuverAt = 400
        s.fixTime = now.timeIntervalSinceReferenceDate
        s.destinationName = "Destino de demostración"
        return s
    }

    static func snapshot(layout: DashLayout, theme: DashTheme, now: Date) -> DashSnapshot {
        var s = DashSnapshot()
        s.nav = nav(now: now)
        s.music = MusicSnapshot(
            available: true, source: "Música", title: "Canción de demostración", artist: "Artista de ejemplo",
            album: "Álbum de ejemplo",
            playing: true, duration: 214, position: 73, positionTime: now.timeIntervalSinceReferenceDate,
            artwork: artwork, palette: palette
        )
        let t = now.timeIntervalSinceReferenceDate
        s.notices = [
            NoticeSnapshot(id: 1, kind: .nav, title: "Ruta iniciada", text: "18 min hasta el destino", time: t - 20),
            NoticeSnapshot(id: 2, kind: .battery, title: "Batería del iPhone", text: "Queda 20 %", time: t - 150),
        ]
        s.layout = layout
        s.theme = theme
        s.night = theme == .dark || (theme == .auto && SunClock.isNightByClock(now))
        s.demo = true
        return s
    }
}
