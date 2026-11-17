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
    case maneuver, music, trip, notices, clock, compass

    static let editable: [OverlayItem] = [.maneuver, .music, .trip, .notices, .clock]

    var title: String {
        switch self {
        case .maneuver: return "Próxima maniobra"
        case .music: return "Música"
        case .trip: return "Llegada y distancia"
        case .notices: return "Avisos"
        case .clock: return "Reloj"
        case .compass: return "Brújula"
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
        case .compass: return true
        }
    }

    mutating func set(_ item: OverlayItem, on: Bool) {
        switch item {
        case .maneuver: maneuver = on
        case .music: music = on
        case .trip: trip = on
        case .notices: notices = on
        case .clock: clock = on
        case .compass: break
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
        }
    }

    mutating func move(_ item: OverlayItem, to spot: CardSpot) {
        switch item {
        case .maneuver: maneuverSpot = spot
        case .music: musicSpot = spot
        case .trip: tripSpot = spot
        case .notices: noticesSpot = spot
        case .clock: clockSpot = spot
        case .compass: break
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
    case gps, gpsMusic, music, custom, full, gpsNotices, musicNotices
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gps: return "Navegación completa"
        case .gpsMusic: return "Navegación + Música"
        case .music: return "Música"
        case .custom: return "Personalizado"
        case .full: return "Panel completo"
        case .gpsNotices: return "Navegación + Avisos"
        case .musicNotices: return "Música + Avisos"
        }
    }
    /// Letra de los cuatro modos principales (A–D).
    var letter: String? {
        switch self {
        case .gps: return "A"
        case .gpsMusic: return "B"
        case .music: return "C"
        case .custom: return "D"
        default: return nil
        }
    }
    var label: String { letter.map { "\($0) · \(title)" } ?? title }
    var short: String {
        switch self {
        case .gps: return "A · Navegación"
        case .gpsMusic: return "B · Nav + Música"
        case .music: return "C · Música"
        case .custom: return "D · Personal"
        case .full: return "Completo"
        case .gpsNotices: return "Nav + Avisos"
        case .musicNotices: return "Música + Avisos"
        }
    }
    static let primary: [DashMode] = [.gps, .gpsMusic, .music, .custom]
    static let others: [DashMode] = [.full, .gpsNotices, .musicNotices]
}

enum DashTheme: String, Codable, CaseIterable, Identifiable {
    case auto, dark, light
    var id: String { rawValue }
    var title: String { self == .auto ? "Automático" : (self == .dark ? "Oscuro" : "Claro") }
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
    var theme: DashTheme = .dark
}

struct DashRules: Codable, Equatable {
    var navStartsGpsMusic = true
    var navEndRestores = true
    var musicOnlyWithoutRoute = false
    var turnPriority = true
}

struct DashConfig: Codable, Equatable {
    /// 2: versión 0.5 (mapa completo). Las configuraciones sin número son de la 0.4.
    var version = 2
    var mode: DashMode = .gpsMusic
    var custom = DashLayout.preset(.custom)
    var theme: DashTheme = .dark
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

    /// Pasa una configuración de la 0.4 al panel nuevo sin perder lo que el usuario creó.
    mutating func migrate() {
        guard version < 2 else { return }
        version = 2
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
        case .maneuver: return o.maneuverSize == .large ? CGSize(width: 340, height: 176) : CGSize(width: 300, height: 150)
        case .music: return o.musicSize == .large ? CGSize(width: 300, height: 124) : CGSize(width: 262, height: 84)
        case .trip: return CGSize(width: 420, height: 50)
        case .notices: return CGSize(width: 262, height: 58)
        case .clock: return CGSize(width: 136, height: 46)
        case .compass: return CGSize(width: 44, height: 44)
        }
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
        let used = Set(placed.map { o.spot($0.item) })
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
    var playing = false
    var duration: Double = 0
    var position: Double = 0
    /// Momento en que se leyó `position` (segundos desde la fecha de referencia).
    var positionTime: TimeInterval = 0
    var artwork: CGImage?
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
            playing: true, duration: 214, position: 73, positionTime: now.timeIntervalSinceReferenceDate, artwork: nil
        )
        let t = now.timeIntervalSinceReferenceDate
        s.notices = [
            NoticeSnapshot(id: 1, kind: .nav, title: "Ruta iniciada", text: "18 min hasta el destino", time: t - 20),
            NoticeSnapshot(id: 2, kind: .battery, title: "Batería del iPhone", text: "Queda 20 %", time: t - 150),
        ]
        s.layout = layout
        s.theme = theme
        s.demo = true
        return s
    }
}
