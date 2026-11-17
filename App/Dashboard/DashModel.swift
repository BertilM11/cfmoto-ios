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
    case full, columns, mainSide
    var id: String { rawValue }
    var slotCount: Int { self == .full ? 1 : (self == .columns ? 2 : 3) }
    var title: String {
        switch self {
        case .full: return "1 zona"
        case .columns: return "2 columnas"
        case .mainSide: return "Principal + 2"
        }
    }
}

enum DashMode: String, Codable, CaseIterable, Identifiable {
    case gps, music, gpsMusic, gpsNotices, musicNotices, full, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gps: return "Solo GPS"
        case .music: return "Solo música"
        case .gpsMusic: return "GPS + Música"
        case .gpsNotices: return "GPS + Avisos"
        case .musicNotices: return "Música + Avisos"
        case .full: return "Panel completo"
        case .custom: return "Personalizado"
        }
    }
}

enum DashTheme: String, Codable, CaseIterable, Identifiable {
    case auto, dark, light
    var id: String { rawValue }
    var title: String { self == .auto ? "Automático" : (self == .dark ? "Oscuro" : "Claro") }
}

struct DashLayout: Codable, Equatable {
    var template: DashTemplate = .mainSide
    var slots: [DashModule?] = [.nav, .music, .notices]
    /// Parte del ancho para la zona principal.
    var split: Double = 0.6
    /// Parte del alto para la zona lateral de arriba (solo en "Principal + 2").
    var sideSplit: Double = 0.46
    /// Zona principal a la derecha.
    var mirrored = false

    static let splitRange = 0.4...0.75
    static let sideRange = 0.3...0.7

    static func preset(_ mode: DashMode) -> DashLayout {
        switch mode {
        case .gps: return DashLayout(template: .full, slots: [.nav])
        case .music: return DashLayout(template: .full, slots: [.music])
        case .gpsMusic: return DashLayout(template: .columns, slots: [.nav, .music], split: 0.64)
        case .gpsNotices: return DashLayout(template: .columns, slots: [.nav, .notices], split: 0.64)
        case .musicNotices: return DashLayout(template: .columns, slots: [.music, .notices], split: 0.58)
        case .full, .custom: return DashLayout()
        }
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

    var showsRoute: Bool { slots.contains { $0?.showsRoute == true } }
    var showsMusic: Bool { slots.contains { $0 == .music } }

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
    var mode: DashMode = .full
    var custom = DashLayout()
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

    var layout: DashLayout { (mode == .custom ? custom : DashLayout.preset(mode)).normalized }

    static var defaultProfiles: [DashProfile] {
        [
            DashProfile(name: "Navegación diaria", layout: .preset(.gpsMusic)),
            DashProfile(name: "Viaje largo", layout: DashLayout(template: .mainSide, slots: [.nav, .trip, .music], split: 0.62, sideSplit: 0.42)),
            DashProfile(name: "Música", layout: .preset(.musicNotices)),
            DashProfile(name: "Ciudad", layout: .preset(.full)),
            DashProfile(name: "Personalizado 1", layout: DashLayout(template: .columns, slots: [.turn, .map], split: 0.55)),
            DashProfile(name: "Personalizado 2", layout: DashLayout(template: .mainSide, slots: [.map, .turn, .trip], split: 0.5, sideSplit: 0.55, mirrored: true)),
        ]
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decoded(_ data: Data) -> DashConfig? { try? JSONDecoder().decode(DashConfig.self, from: data) }
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
