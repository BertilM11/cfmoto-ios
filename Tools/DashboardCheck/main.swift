// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pruebas del panel (sin moto y sin iPhone) y láminas de cada modo. Se compila en macOS junto
// con el modelo y el dibujo de la app:
//   swiftc Tools/DashboardCheck/main.swift App/HUD/HUDModel.swift App/HUD/HUDRenderer.swift \
//          App/Dashboard/DashModel.swift App/Dashboard/DashRenderer.swift \
//          App/Dashboard/MapBase.swift App/Dashboard/DashMapRenderer.swift -o dashcheck
//   ./dashcheck carpeta_de_salida
// El mapa de calles real (Apple Maps) solo existe en el iPhone; aquí se usa un mapa de prueba
// dibujado por el propio programa para comprobar la proyección y el dibujo encima.
import Foundation
import CoreGraphics
import ImageIO

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
var failures = 0
var report: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if !ok { failures += 1 }
    let line = (ok ? "PASA   " : "FALLA  ") + name + (detail.isEmpty ? "" : " — " + detail)
    report.append(line)
    print(line)
}

func save(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
    if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

var components = DateComponents()
components.year = 2026
components.month = 11
components.day = 17
components.hour = 19
components.minute = 4
let now = Calendar.current.date(from: components) ?? Date()

let W: CGFloat = 800
let H: CGFloat = 400
HUDRenderer.reservedBottom = 0

// 1. La imagen se usa entera: la moto pone sus indicadores en su propia franja, debajo.
let fullArea = DashLayoutEngine.usableArea(width: W, height: H, reservedBottom: 0)
check("Por defecto se usa toda la imagen (800x400)", fullArea.height == H && HUDRenderer(width: 800, height: 400).height == 400)
check("La franja vacía solo existe si el usuario la pide", DashLayoutEngine.usableArea(width: W, height: H, reservedBottom: 0.22).height == 312)

// 2. Distribución por zonas: dentro del área, sin solapes, sin módulos repetidos.
let area = fullArea.insetBy(dx: 5, dy: 5)
func layoutProblems(_ layout: DashLayout) -> String? {
    let frames = DashLayoutEngine.frames(layout, in: area, gap: 5)
    var seen = Set<DashModule>()
    for f in frames {
        if !area.insetBy(dx: -0.5, dy: -0.5).contains(f.rect) { return "fuera del área: \(f.module)" }
        if f.rect.width < 80 || f.rect.height < 60 { return "zona demasiado pequeña: \(f.module) \(f.rect.size)" }
        if seen.contains(f.module) { return "módulo repetido: \(f.module)" }
        seen.insert(f.module)
    }
    for i in 0..<frames.count {
        for j in (i + 1)..<max(i + 1, frames.count) {
            let x = frames[i].rect.intersection(frames[j].rect)
            if !x.isNull && x.width > 0.5 && x.height > 0.5 { return "solape entre \(frames[i].module) y \(frames[j].module)" }
        }
    }
    return nil
}

var generator = SystemRandomNumberGenerator()
var randomProblem: String?
for _ in 0..<2000 {
    var l = DashLayout()
    l.template = DashTemplate.allCases.randomElement(using: &generator)!
    l.slots = (0..<Int.random(in: 0...4, using: &generator)).map { _ in
        Bool.random(using: &generator) ? DashModule.allCases.randomElement(using: &generator) : nil
    }
    l.split = Double.random(in: -1...2, using: &generator)
    l.sideSplit = Double.random(in: -1...2, using: &generator)
    l.mirrored = Bool.random(using: &generator)
    if let p = layoutProblems(l) {
        randomProblem = p
        break
    }
}
check("2000 diseños por zonas al azar (incluye valores inválidos)", randomProblem == nil, randomProblem ?? "")

// 3. Tarjetas sobre el mapa: dentro de la imagen, sin montarse, con la maniobra siempre visible.
func cardProblems(_ o: OverlaySettings, k: CGFloat = 1, notices: Bool = true) -> String? {
    let a = CGRect(x: 0, y: 0, width: W * k, height: H * k)
    let cards = DashLayoutEngine.overlayCards(o, in: a, k: k, showNotices: notices)
    let inner = a.insetBy(dx: 12 * k - 0.6, dy: 12 * k - 0.6)
    for c in cards where !inner.contains(c.rect) { return "\(c.item) se sale: \(c.rect)" }
    for i in 0..<cards.count {
        for j in (i + 1)..<max(i + 1, cards.count) where cards[i].rect.intersects(cards[j].rect) {
            let x = cards[i].rect.intersection(cards[j].rect)
            if x.width > 0.5 && x.height > 0.5 { return "\(cards[i].item) y \(cards[j].item) se montan" }
        }
    }
    if o.maneuver && !cards.contains(where: { $0.item == .maneuver }) { return "falta la maniobra" }
    if !cards.contains(where: { $0.item == .compass }) { return "falta la brújula" }
    let total = cards.reduce(CGFloat(0)) { $0 + $1.rect.width * $1.rect.height }
    if total > a.width * a.height * 0.5 { return "las tarjetas tapan más de la mitad del mapa" }
    return nil
}

for mode in DashMode.allCases where DashLayout.preset(mode).template == .overlay {
    let p = cardProblems(DashLayout.preset(mode).overlay)
    check("Tarjetas del modo «\(mode.label)»", p == nil, p ?? "")
}
var cardProblem: String?
for _ in 0..<3000 {
    var o = OverlaySettings()
    for item in OverlayItem.editable {
        o.set(item, on: Bool.random(using: &generator))
        o.move(item, to: CardSpot.allCases.randomElement(using: &generator)!)
        if !Bool.random(using: &generator) { o.set(item, on: false) }
        if item.resizable { o.resize(item, to: CardSize.allCases.randomElement(using: &generator)!) }
    }
    let k = [CGFloat(0.8), 1, 1.6].randomElement(using: &generator)!
    if let p = cardProblems(o, k: k, notices: Bool.random(using: &generator)) {
        cardProblem = p
        break
    }
}
check("3000 combinaciones de tarjetas, lugares y tamaños al azar", cardProblem == nil, cardProblem ?? "")

// 4. Contenido de cada modo.
func overlay(_ mode: DashMode) -> OverlaySettings { DashLayout.preset(mode).overlay }
check("A · Navegación completa: mapa, maniobra y viaje, sin música grande",
      DashLayout.preset(.gps).template == .overlay && overlay(.gps).maneuver && overlay(.gps).trip && !overlay(.gps).music)
check("B · Navegación + Música: mapa con música compacta",
      DashLayout.preset(.gpsMusic).template == .overlay && overlay(.gpsMusic).music && overlay(.gpsMusic).musicSize == .compact)
check("C · Música: pantalla dedicada", DashLayout.preset(.music).template == .full && DashLayout.preset(.music).slots == [.music])
check("D · Personalizado arranca con el mapa completo", DashConfig().custom.template == .overlay)
check("Los otros modos se conservan", DashMode.others == [.full, .gpsNotices, .musicNotices]
      && DashLayout.preset(.musicNotices).normalized.slots == [.music, .notices])
check("Los modos con mapa muestran la ruta", DashLayout.preset(.gps).showsRoute && DashLayout.preset(.gpsMusic).showsRoute && !DashLayout.preset(.music).showsRoute)

// 5. Edición.
var edit = DashLayout(template: .mainSide, slots: [.nav, .music, .notices])
edit.swapSlots(0, 2)
check("Intercambiar dos zonas", edit.slots == [.notices, .music, .nav])
edit.place(.music, at: 0)
check("Colocar un módulo que ya estaba en otra zona los intercambia", edit.slots == [.music, .notices, .nav])
edit.place(nil, at: 1)
check("Ocultar un módulo deja la zona vacía", edit.slots == [.music, nil, .nav] && layoutProblems(edit) == nil)
edit.template = .columns
check("Cambiar de plantilla recorta las zonas sobrantes", edit.normalized.slots.count == 2)
var ov = OverlaySettings()
ov.swap(.maneuver, .music)
check("Intercambiar dos tarjetas", ov.maneuverSpot == .topRight && ov.musicSpot == .topLeft)
ov.move(.trip, to: .bottomLeft)
ov.resize(.music, to: .large)
ov.set(.notices, on: false)
check("Mover, agrandar y ocultar tarjetas", ov.tripSpot == .bottomLeft && ov.musicSize == .large && !ov.notices && cardProblems(ov) == nil)
var toOverlay = DashLayout(template: .columns, slots: [.nav, .music])
toOverlay.setTemplate(.overlay)
check("Pasar a «Mapa completo» desde zonas", toOverlay.template == .overlay && toOverlay.normalized.slots.isEmpty)

// 6. Persistencia y actualización desde la 0.4.
var config = DashConfig()
config.mode = .custom
config.custom = DashLayout(template: .columns, slots: [.map, .trip], split: 0.5)
config.theme = .light
config.rules.turnPriority = false
config.noticeSeconds = 15
config.map.style = .muted
config.map.threeD = false
config.musicProvider = .spotify
config.spotifyClientID = "id-de-prueba"
config.profiles.append(DashProfile(name: "Prueba", layout: .preset(.music)))
if let data = config.encoded(), let back = DashConfig.decoded(data) {
    check("La configuración se guarda y se recupera igual", back == config)
} else {
    check("La configuración se guarda y se recupera igual", false, "no se pudo codificar")
}
check("Datos guardados dañados no rompen la carga", DashConfig.decoded(Data("basura".utf8)) == nil)
check("Hay seis perfiles de fábrica", DashConfig().profiles.count == 6)
let legacy = """
{"mode":"full","custom":{"template":"mainSide","slots":["nav","music","notices"],"split":0.6,"sideSplit":0.46,"mirrored":false},
"theme":"dark","rules":{"navStartsGpsMusic":true,"navEndRestores":true,"musicOnlyWithoutRoute":false,"turnPriority":true},
"profiles":[
 {"id":"9C1C0D3E-1111-4E55-8C77-000000000001","name":"Navegación diaria","layout":{"template":"columns","slots":["nav","music"],"split":0.64,"sideSplit":0.46,"mirrored":false},"theme":"dark"},
 {"id":"9C1C0D3E-1111-4E55-8C77-000000000002","name":"Mi perfil","layout":{"template":"columns","slots":["music","clock"],"split":0.5,"sideSplit":0.46,"mirrored":false},"theme":"light"}],
"noticeSeconds":12,"noticePrivacy":true,"noticeNav":true,"noticeLink":false,"noticeBattery":true,"showArtwork":true,"showProgress":false}
"""
if let old = DashConfig.decoded(Data(legacy.utf8)) {
    check("Configuración de la 0.4: se carga", true)
    check("Configuración de la 0.4: se conservan modo, avisos y perfiles del usuario",
          old.mode == .full && old.noticeSeconds == 12 && old.noticePrivacy && !old.noticeLink && !old.showProgress
          && old.profiles.count == 2 && old.profiles[1].name == "Mi perfil" && old.profiles[1].layout.slots == [.music, .clock])
    check("Configuración de la 0.4: los perfiles de fábrica pasan al mapa completo",
          old.profiles[0].layout.template == .overlay && old.version == 2)
    check("Configuración de la 0.4: mapa con valores de fábrica", old.map == MapSettings() && old.musicProvider == .appleMusic)
} else {
    check("Configuración de la 0.4: se carga", false)
}

// 7. Reglas automáticas.
var c = DashConfig()
var auto = DashAutoState()
c.mode = .music
DashRulesEngine.apply(.navStarted, config: &c, auto: &auto)
check("Iniciar ruta en Música pasa a Navegación + Música", c.mode == .gpsMusic && auto.saved == .music)
DashRulesEngine.apply(.navEnded, config: &c, auto: &auto)
check("Terminar la ruta vuelve al modo anterior", c.mode == .music && auto.saved == nil)
c.mode = .full
DashRulesEngine.apply(.navStarted, config: &c, auto: &auto)
check("Iniciar ruta no cambia un modo que ya muestra el mapa", c.mode == .full)
c.mode = .gps
c.rules.musicOnlyWithoutRoute = true
DashRulesEngine.apply(.musicStarted(routeActive: true), config: &c, auto: &auto)
check("Música con ruta activa no quita el mapa", c.mode == .gps)
DashRulesEngine.apply(.musicStarted(routeActive: false), config: &c, auto: &auto)
check("Música sin ruta pasa a Música", c.mode == .music)
auto = DashAutoState()
c.mode = .musicNotices
c.rules.navStartsGpsMusic = false
DashRulesEngine.apply(.turnNear, config: &c, auto: &auto)
check("Giro próximo da prioridad a las indicaciones", c.mode == .gps)
DashRulesEngine.apply(.turnPassed, config: &c, auto: &auto)
check("Pasado el giro vuelve el modo anterior", c.mode == .musicNotices)
c.rules = DashRules(navStartsGpsMusic: false, navEndRestores: false, musicOnlyWithoutRoute: false, turnPriority: false)
c.mode = .music
DashRulesEngine.apply(.navStarted, config: &c, auto: &auto)
DashRulesEngine.apply(.turnNear, config: &c, auto: &auto)
DashRulesEngine.apply(.musicStarted(routeActive: false), config: &c, auto: &auto)
check("Con las reglas apagadas no hay cambios automáticos", c.mode == .music)

// 8. Proyección del mapa: un mapa visto en perspectiva es una homografía exacta.
let truth = Homography(m: [0.31, -0.12, 0.5, 0.04, 0.27, 0.62, 0.015, -0.11, 1])
let corners: [(Double, Double)] = [(-0.7, -0.6), (0.8, -0.5), (0.6, 0.9), (-0.9, 0.7)]
var images: [(Double, Double)] = []
for (x, y) in corners {
    let q = truth.apply(x, y) ?? .zero
    images.append((Double(q.x), Double(q.y)))
}
if let fitted = Homography.fit(from: corners, to: images) {
    var worst = 0.0
    for _ in 0..<500 {
        let x = Double.random(in: -1...1, using: &generator)
        let y = Double.random(in: -1...1, using: &generator)
        if let a = truth.apply(x, y), let b = fitted.apply(x, y) {
            worst = max(worst, Double(hypot(a.x - b.x, a.y - b.y)))
        }
    }
    check("Homografía: 4 puntos bastan para situar cualquier otro", worst < 1e-9, String(format: "error máximo %.2e", worst))
} else {
    check("Homografía: 4 puntos bastan para situar cualquier otro", false, "no se pudo calcular")
}
check("Homografía: puntos alineados se rechazan", Homography.fit(from: [(0, 0), (1, 1), (2, 2), (3, 3)], to: [(0, 0), (1, 0), (2, 0), (3, 0)]) == nil)

// Cámara de prueba: mapa girado (rumbo 35°), 600 m de alto visible, centro en Ciudad de Guatemala.
let center = GeoPoint(lat: 14.6349, lon: -90.5069)
let heading = 35.0
let visible = 600.0
func camera(_ g: GeoPoint) -> CGPoint {
    let dy = (g.lat - center.lat) * 110_574.0
    let dx = (g.lon - center.lon) * 111_320.0 * cos(center.lat * .pi / 180)
    let h = heading * .pi / 180
    let forward = dx * sin(h) + dy * cos(h)
    let right = dx * cos(h) - dy * sin(h)
    return CGPoint(x: 0.5 + right / (visible * 2), y: 0.5 - forward / visible)
}
let samplePoints = [center.moved(100, bearing: 0).moved(100, bearing: 90), center.moved(100, bearing: 0).moved(100, bearing: 270),
                    center.moved(100, bearing: 180).moved(100, bearing: 270), center.moved(100, bearing: 180).moved(100, bearing: 90)]

// Imagen de calles de prueba (cuadrícula alineada con la cámara), solo para estas pruebas.
func testStreets(night: Bool) -> CGImage? {
    let w = 800
    let h = 400
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(night ? CGColor(srgbRed: 0.11, green: 0.13, blue: 0.17, alpha: 1) : CGColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setStrokeColor(night ? CGColor(srgbRed: 0.25, green: 0.29, blue: 0.36, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    // Calles cada 100 m en las dos direcciones del mundo, vistas con la cámara de prueba.
    ctx.setLineWidth(9)
    for i in -12...12 {
        for vertical in [true, false] {
            var pts: [CGPoint] = []
            for j in -12...12 {
                let g = vertical
                    ? center.moved(Double(i) * 100, bearing: 90).moved(Double(j) * 100, bearing: 0)
                    : center.moved(Double(i) * 100, bearing: 0).moved(Double(j) * 100, bearing: 90)
                let q = camera(g)
                pts.append(CGPoint(x: q.x * 800, y: q.y * 400))
            }
            ctx.addLines(between: pts)
            ctx.strokePath()
        }
    }
    return ctx.makeImage()
}

let base = MapBase(
    image: testStreets(night: true), data: nil, pixelWidth: 800, pixelHeight: 400, center: center, heading: heading,
    pitch: 0, night: true, live: true, created: now.timeIntervalSinceReferenceDate, styleKey: "prueba",
    samples: samplePoints.map { ($0, camera($0)) }
)
if let base = base {
    var worst = 0.0
    for _ in 0..<500 {
        let g = center.moved(Double.random(in: 0...280, using: &generator), bearing: Double.random(in: 0...360, using: &generator))
        if let p = base.project(g) {
            let q = camera(g)
            worst = max(worst, Double(hypot((p.x - q.x) * 800, (p.y - q.y) * 400)))
        } else {
            worst = 1e9
        }
    }
    check("Mapa de calles: la ruta cae donde la pinta la cámara (menos de 1 píxel)", worst < 1, String(format: "error máximo %.3f px", worst))
} else {
    check("Mapa de calles: la ruta cae donde la pinta la cámara (menos de 1 píxel)", false, "no se pudo crear el mapa")
}

// Ruta de prueba sobre las calles de prueba: 300 m al rumbo de la cámara y giro a la derecha.
func streetsSnapshot(_ layout: DashLayout, theme: DashTheme) -> DashSnapshot {
    var s = DashDemo.snapshot(layout: layout, theme: theme, now: now)
    let start = center.moved(250, bearing: heading + 180)
    let frame = GeoFrame(origin: start)
    var pts: [CGPoint] = []
    for i in 0...30 { pts.append(frame.local(start.moved(Double(i) * 15, bearing: heading))) }
    let corner = start.moved(450, bearing: heading)
    for i in 1...30 { pts.append(frame.local(corner.moved(Double(i) * 15, bearing: heading + 90))) }
    s.nav.shape = HUDRouteShape(points: pts)
    s.nav.geo = frame
    s.nav.progress = 160
    s.nav.speed = 0
    s.nav.maneuverAt = 450
    s.nav.distanceToManeuver = 290
    s.nav.fixTime = now.timeIntervalSinceReferenceDate
    s.map = base
    s.mapSettings = MapSettings()
    return s
}

// 9. Composición: cada modo dibuja algo y usa toda la imagen.
func pixels(_ s: DashSnapshot) -> (image: CGImage?, data: [UInt8], rowBytes: Int) {
    let w = Int(W)
    let h = Int(H)
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    var image: CGImage?
    data.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        HUDRenderer(width: w, height: h).drawDashboard(s, now: now, in: ctx)
        image = ctx.makeImage()
    }
    return (image, data, w * 4)
}

func colors(_ r: (image: CGImage?, data: [UInt8], rowBytes: Int), rows: Range<Int>) -> Int {
    var set = Set<UInt32>()
    for y in stride(from: rows.lowerBound, to: rows.upperBound, by: 2) {
        for x in stride(from: 0, to: Int(W), by: 2) {
            let o = y * r.rowBytes + x * 4
            set.insert((UInt32(r.data[o + 2]) << 16) | (UInt32(r.data[o + 1]) << 8) | UInt32(r.data[o]))
        }
    }
    return set.count
}

for mode in DashMode.allCases {
    for theme in [DashTheme.dark, DashTheme.light] {
        let layout = DashLayout.preset(mode)
        let r = pixels(streetsSnapshot(layout, theme: theme))
        let name = "«\(mode.label)» \(theme == .dark ? "oscuro" : "claro")"
        check("Composición \(name)", r.image != nil && colors(r, rows: 0..<Int(H)) > 20)
        let bottom = colors(r, rows: Int(H * 0.8)..<Int(H))
        check("Sin franja vacía abajo en \(name)", bottom > 6, "\(bottom) colores en el 20 % inferior")
        if let image = r.image { save(image, "panel-\(mode.rawValue)-\(theme.rawValue)") }
    }
}

// La ruta se dibuja encima de la calle correcta del mapa de prueba.
let check1 = pixels(streetsSnapshot(.preset(.gps), theme: .dark))
if let p = base?.project(center.moved(250, bearing: heading + 180).moved(380, bearing: heading)) {
    let x = Int(p.x * W)
    let y = Int(p.y * H)
    let o = y * check1.rowBytes + x * 4
    let b = Int(check1.data[o])
    let g = Int(check1.data[o + 1])
    let rr = Int(check1.data[o + 2])
    check("La ruta azul se dibuja sobre su calle del mapa", b > 180 && b > rr + 60 && b > g, "color en la ruta: r\(rr) g\(g) b\(b)")
} else {
    check("La ruta azul se dibuja sobre su calle del mapa", false, "punto fuera del mapa")
}

// Con la franja vacía activada a petición del usuario, esa parte queda lisa.
HUDRenderer.reservedBottom = 0.22
let reservedTop = Int(DashLayoutEngine.usableArea(width: W, height: H, reservedBottom: 0.22).height)
let reserved = pixels(streetsSnapshot(.preset(.gpsMusic), theme: .dark))
check("Si se pide dejar la franja vacía, queda lisa", colors(reserved, rows: reservedTop + 1..<Int(H)) == 1)
HUDRenderer.reservedBottom = 0

// 10. Estados sin datos.
var empty = DashSnapshot()
empty.layout = .preset(.full)
let e = pixels(empty)
check("Panel completo sin ruta, sin música, sin avisos y sin mapa", e.image != nil)
if let image = e.image { save(image, "panel-sin-datos") }
var vector = DashDemo.snapshot(layout: .preset(.gpsMusic), theme: .dark, now: now)
vector.mapSettings.streets = true
let v = pixels(vector)
check("Sin imagen de calles se dibuja el mapa simple de la ruta", v.image != nil && colors(v, rows: 0..<Int(H)) > 20)
if let image = v.image { save(image, "panel-mapa-simple") }
var none = DashSnapshot()
none.layout = DashLayout(template: .columns, slots: [nil, nil])
check("Panel sin módulos no falla", pixels(none).image != nil)
var arrived = streetsSnapshot(.preset(.gpsMusic), theme: .dark)
arrived.nav.navigating = false
arrived.nav.arrived = true
arrived.nav.destinationName = "Destino de demostración"
if let image = pixels(arrived).image { save(image, "panel-llegada") }
var music = streetsSnapshot(.preset(.music), theme: .dark)
music.music.artwork = nil
let mr = pixels(music)
check("Modo Música con ruta: muestra el próximo giro abajo", mr.image != nil && colors(mr, rows: Int(H * 0.82)..<Int(H)) > 6)
var small = streetsSnapshot(.preset(.full), theme: .dark)
small.privacy = true
check("Otra resolución (640x320)", DashPreview.image(small, width: 640, height: 320, now: now) != nil)
if let image = DashPreview.image(small, width: 640, height: 320, now: now) { save(image, "panel-640x320") }

// 11. Rendimiento del dibujo (mapa de calles + tarjetas).
let renderer = HUDRenderer(width: Int(W), height: Int(H))
let snap = streetsSnapshot(.preset(.full), theme: .dark)
let start = Date()
for _ in 0..<100 { _ = DashPreview.image(snap, now: now, renderer: renderer) }
let ms = Date().timeIntervalSince(start) * 10
check("Dibujar un fotograma con mapa y tarjetas tarda menos de 25 ms", ms < 25, String(format: "%.1f ms de media en esta máquina", ms))

let summary = failures == 0 ? "RESULTADO: \(report.count) pruebas, todas pasan" : "RESULTADO: \(failures) de \(report.count) pruebas fallan"
print(summary)
report.append(summary)
try? report.joined(separator: "\n").write(toFile: outDir + "/pruebas-panel.txt", atomically: true, encoding: .utf8)
exit(failures == 0 ? 0 : 1)
