// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pruebas del panel (sin moto y sin iPhone) y láminas de cada modo. Se compila en macOS junto
// con el modelo y el dibujo de la app:
//   swiftc Tools/DashboardCheck/main.swift App/HUD/HUDModel.swift App/HUD/HUDRenderer.swift \
//          App/Dashboard/DashModel.swift App/Dashboard/DashRenderer.swift \
//          App/Dashboard/MapBase.swift App/Dashboard/DashMapRenderer.swift App/Dashboard/Appearance.swift \
//          App/Dashboard/MapCorridor.swift -o dashcheck
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
    if cards.first(where: { $0.item == .time })?.rect != DashLayoutEngine.statusClock(in: a, k: k) { return "la hora no está en su sitio" }
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
check("1 · Navegación completa: mapa, maniobra y viaje, sin música grande",
      DashLayout.preset(.gps).template == .overlay && overlay(.gps).maneuver && overlay(.gps).trip && !overlay(.gps).music)
check("2 · Navegación + música compacta",
      DashLayout.preset(.gpsMusic).template == .overlay && overlay(.gpsMusic).music && overlay(.gpsMusic).musicSize == .compact)
check("3 · Pantalla dividida: mapa a la izquierda y música ampliada a la derecha",
      DashLayout.preset(.split).template == .columns && DashLayout.preset(.split).normalized.slots == [.nav, .music]
      && !DashLayout.preset(.split).mirrored && layoutProblems(DashLayout.preset(.split)) == nil)
check("4 · Música completa: pantalla dedicada", DashLayout.preset(.music).template == .full && DashLayout.preset(.music).slots == [.music])
check("5 · Personalizado arranca con el mapa completo", DashConfig().custom.template == .overlay)
check("Los cinco modos principales van numerados del 1 al 5", DashMode.primary.compactMap { $0.number } == [1, 2, 3, 4, 5])
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
check("Por defecto: día y noche automáticos, guía de CFMoto Link y colores de la portada",
      DashConfig().theme == .auto && DashConfig().navProvider == .cfmoto && DashConfig().musicStyle == .dynamic
      && DashConfig().profiles.allSatisfy { $0.theme == .auto })
var light = DashConfig()
light.theme = .light
light.version = 2
if let data = light.encoded(), let back = DashConfig.decoded(data) {
    check("Si el usuario eligió claro, se respeta al actualizar", back.theme == .light && back.version == 3)
}
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
          old.profiles[0].layout.template == .overlay && old.version == 3)
    check("Configuración vieja con tema oscuro fijo pasa a automático (el claro elegido se respeta)",
          old.theme == .auto && old.profiles[0].theme == .auto && old.profiles[1].theme == .light)
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

// 8b. Día y noche por el sol (Ciudad de Guatemala, 17 de noviembre de 2026, UTC−6).
var gt = Calendar(identifier: .gregorian)
gt.timeZone = TimeZone(secondsFromGMT: -6 * 3600)!
func gtDate(_ h: Int, _ m: Int) -> Date {
    gt.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: h, minute: m))!
}
let gLat = 14.6349
let gLon = -90.5069
if let sun = SunClock.times(on: gtDate(12, 0), lat: gLat, lon: gLon) {
    let rise = gt.dateComponents([.hour, .minute], from: sun.sunrise)
    let set = gt.dateComponents([.hour, .minute], from: sun.sunset)
    let riseMin = (rise.hour ?? 0) * 60 + (rise.minute ?? 0)
    let setMin = (set.hour ?? 0) * 60 + (set.minute ?? 0)
    check("Amanecer en Guatemala hacia las 6:05", riseMin > 5 * 60 + 45 && riseMin < 6 * 60 + 25, String(format: "%d:%02d", rise.hour ?? 0, rise.minute ?? 0))
    check("Atardecer en Guatemala hacia las 17:30", setMin > 17 * 60 + 5 && setMin < 17 * 60 + 45, String(format: "%d:%02d", set.hour ?? 0, set.minute ?? 0))
} else {
    check("Amanecer y atardecer en Guatemala", false, "sin resultado")
}
check("Día a las 9:00, 12:00 y 16:30", SunClock.isNight(at: gtDate(9, 0), lat: gLat, lon: gLon) == false
      && SunClock.isNight(at: gtDate(12, 0), lat: gLat, lon: gLon) == false && SunClock.isNight(at: gtDate(16, 30), lat: gLat, lon: gLon) == false)
check("Noche a las 5:00, 18:30 y 23:00", SunClock.isNight(at: gtDate(5, 0), lat: gLat, lon: gLon) == true
      && SunClock.isNight(at: gtDate(18, 30), lat: gLat, lon: gLon) == true && SunClock.isNight(at: gtDate(23, 0), lat: gLat, lon: gLon) == true)
check("Sin posición se decide por la hora", SunClock.isNightByClock(gtDate(21, 0), calendar: gt) && !SunClock.isNightByClock(gtDate(10, 0), calendar: gt))

// 8c. Colores de la portada.
func artwork(_ draw: (CGContext) -> Void) -> CGImage? {
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
    draw(ctx)
    return ctx.makeImage()
}
let redBlack = artwork { ctx in
    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.02, blue: 0.02, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.08, blue: 0.1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 70))
}
let blue = artwork { ctx in
    ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.35, blue: 0.85, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.95, alpha: 1))
    ctx.fill(CGRect(x: 40, y: 40, width: 30, height: 30))
}
let pale = artwork { ctx in
    ctx.setFillColor(CGColor(srgbRed: 0.98, green: 0.96, blue: 0.86, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.7, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 40))
}
func hueNear(_ c: RGB, _ target: Double, _ tolerance: Double) -> Bool {
    var d = abs(c.hsl.h - target)
    if d > 180 { d = 360 - d }
    return d <= tolerance
}
check("Contraste: blanco sobre negro es 21:1", abs(RGB(1, 1, 1).contrast(with: RGB(0, 0, 0)) - 21) < 0.01)
if let rb = redBlack.flatMap({ ArtPalette.extract($0) }), let bl = blue.flatMap({ ArtPalette.extract($0) }), let pl = pale.flatMap({ ArtPalette.extract($0) }) {
    check("Portada roja y negra: color dominante rojo", hueNear(rb.base, 0, 20) && rb.base.hsl.s > 0.5)
    check("Portada azul: color dominante azul", hueNear(bl.base, 220, 25))
    var worst = 100.0
    for pal in [rb, bl, pl] {
        for night in [true, false] {
            for intensity in [0.2, 0.75, 1.0] {
                let c = MusicCardColors.make(style: .dynamic, palette: pal, night: night, intensity: intensity)
                worst = min(worst, c.text.contrast(with: c.top), c.text.contrast(with: c.bottom))
            }
        }
    }
    check("Texto legible sobre cualquier fondo de portada (contraste ≥ 4,5)", worst >= 4.5, String(format: "peor %.1f:1", worst))
    let redCard = MusicCardColors.make(style: .dynamic, palette: rb, night: true, intensity: 1)
    check("La tarjeta toma tonos de la portada (rojo) sin saturar de más", hueNear(redCard.top, 0, 25) && redCard.top.hsl.s <= 0.56)
    let blueCard = MusicCardColors.make(style: .dynamic, palette: bl, night: true, intensity: 1)
    check("Con portada azul el fondo va hacia azul", hueNear(blueCard.top, 220, 30))
    let fixedDark = MusicCardColors.make(style: .dark, palette: rb, night: false, intensity: 1)
    let fixedLight = MusicCardColors.make(style: .light, palette: rb, night: true, intensity: 1)
    check("Fondo oscuro fijo y claro fijo no dependen de la portada",
          fixedDark.top.luminance < 0.05 && fixedLight.top.luminance > 0.8)
    let half = redCard.mixed(with: blueCard, 0.5)
    check("Transición entre canciones: los colores pasan de una a otra", half.top != redCard.top && half.top != blueCard.top)
} else {
    check("Colores de la portada", false, "no se pudieron analizar las portadas de prueba")
}

// 8d. Proveedores de navegación: enlaces oficiales.
let wazeApp = NavProviderID.waze.link(lat: 14.588, lon: -90.5302, name: "Aeropuerto", app: true)?.absoluteString ?? ""
let wazeWeb = NavProviderID.waze.link(lat: 14.588, lon: -90.5302, name: "Aeropuerto", app: false)?.absoluteString ?? ""
let googleApp = NavProviderID.googleMaps.link(lat: 14.588, lon: -90.5302, name: "Aeropuerto", app: true)?.absoluteString ?? ""
let googleWeb = NavProviderID.googleMaps.link(lat: 14.588, lon: -90.5302, name: "Aeropuerto", app: false)?.absoluteString ?? ""
check("Waze: enlace oficial con destino y navegación", wazeApp.hasPrefix("waze://ul?ll=14.588000,-90.530200&navigate=yes")
      && wazeWeb.hasPrefix("https://waze.com/ul?ll=14.588000,-90.530200&navigate=yes"), wazeApp)
check("Google Maps: enlace de la app y de respaldo web", googleApp.hasPrefix("comgooglemaps://?daddr=14.588000,-90.530200&directionsmode=driving")
      && googleWeb.contains("api=1") && googleWeb.contains("destination=14.588000,-90.530200"), googleApp)
check("CFMoto Link no abre ninguna app externa", NavProviderID.cfmoto.link(lat: 0, lon: 0, name: "", app: true) == nil && !NavProviderID.cfmoto.external)
check("Los proveedores externos no prometen giros en la moto",
      NavProviderID.allCases.filter { $0.external }.allSatisfy { p in p.capabilities.contains { $0.0 == "Giros en la moto" && !$0.1 } })

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

// Recta larga con solo dos puntos (Apple devuelve así las avenidas rectas): la línea tiene que
// verse por delante de la moto aunque el siguiente punto de la ruta quede muy fuera de la
// imagen. Antes, en las imágenes planas (las guardadas), no se dibujaba.
var sparse = streetsSnapshot(.preset(.gps), theme: .dark)
let sparseStart = center.moved(250, bearing: heading + 180)
let sparseFrame = GeoFrame(origin: sparseStart)
sparse.nav.shape = HUDRouteShape(points: [sparseFrame.local(sparseStart), sparseFrame.local(sparseStart.moved(3000, bearing: heading))])
sparse.nav.geo = sparseFrame
sparse.nav.maneuverAt = nil
let sparsePixels = pixels(sparse)
if let p = base?.project(sparseStart.moved(380, bearing: heading)) {
    let o = Int(p.y * H) * sparsePixels.rowBytes + Int(p.x * W) * 4
    let b = Int(sparsePixels.data[o])
    let g = Int(sparsePixels.data[o + 1])
    let rr = Int(sparsePixels.data[o + 2])
    check("Recta larga sin puntos intermedios: la ruta se ve por delante de la moto", b > 180 && b > rr + 60 && b > g,
          "color delante de la moto: r\(rr) g\(g) b\(b)")
} else {
    check("Recta larga sin puntos intermedios: la ruta se ve por delante de la moto", false, "punto fuera del mapa")
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

// 10b. Láminas de lo nuevo de la 0.6.
var dyn = streetsSnapshot(.preset(.gpsMusic), theme: .dark)
dyn.music.artwork = redBlack
dyn.music.palette = redBlack.flatMap { ArtPalette.extract($0) }
dyn.music.source = "Spotify"
if let image = pixels(dyn).image { save(image, "panel-musica-colores-noche") }
var dynDay = streetsSnapshot(.preset(.split), theme: .light)
dynDay.music.artwork = blue
dynDay.music.palette = blue.flatMap { ArtPalette.extract($0) }
let splitDay = pixels(dynDay)
check("Pantalla dividida de día con colores de portada", splitDay.image != nil && colors(splitDay, rows: 0..<Int(H)) > 40)
if let image = splitDay.image { save(image, "panel-dividida-dia") }
var ext = streetsSnapshot(.preset(.gpsMusic), theme: .dark)
ext.nav.navigating = false
ext.nav.shape = nil
ext.nav.here = center
ext.nav.course = heading
ext.external = ExternalGuide(provider: .waze, destination: center.moved(4200, bearing: heading + 20), name: "Aeropuerto La Aurora")
let extImg = pixels(ext)
check("Guía en otra app: la moto muestra el destino sin inventar giros", extImg.image != nil)
if let image = extImg.image { save(image, "panel-guia-waze") }
var contrastRoute = streetsSnapshot(.preset(.gps), theme: .dark)
contrastRoute.mapSettings.routeStyle = .highContrast
if let image = pixels(contrastRoute).image { save(image, "panel-ruta-alto-contraste") }
var preview = streetsSnapshot(.preset(.gps), theme: .dark)
preview.nav.navigating = false
preview.nav.here = center.moved(250, bearing: heading + 180)
preview.nav.previewRoutes = [
    (0...20).map { center.moved(-250 + Double($0) * 30, bearing: heading) },
    (0...20).map { center.moved(-250 + Double($0) * 25, bearing: heading).moved(Double($0) * 6, bearing: heading + 90) },
]
preview.nav.previewSelected = 0
preview.nav.previewDistances = [7400, 8100]
preview.nav.previewTimes = [1080, 1260]
let pv = pixels(preview)
check("Vista previa de rutas en la moto antes de empezar", pv.image != nil)
if let image = pv.image { save(image, "panel-rutas-propuestas") }

// 10c. Mapa guardado para el iPhone bloqueado (0.6.1).
// Ruta de prueba de 15 km: 6 km al noreste, giro a la derecha, 4 km, giro a la izquierda, 5 km.
func legs(_ start: GeoPoint, _ parts: [(Double, Double)]) -> [GeoPoint] {
    var pts = [start]
    var here = start
    for (length, bearing) in parts {
        var d = 20.0
        while d <= length {
            pts.append(here.moved(d, bearing: bearing))
            d += 20
        }
        here = here.moved(length, bearing: bearing)
    }
    return pts
}
let corridorStart = GeoPoint(lat: 14.58, lon: -90.55)
let corridorRoute = RoutePath(points: legs(corridorStart, [(6000, 35), (4000, 125), (5000, 35)]))
let corridorVisible = 0.62 * 680
let corridorStep = CorridorPlanner.step(visible: corridorVisible)
check("Ruta de prueba medida bien (15 km)", abs(corridorRoute.length - 15000) < 30, String(format: "%.0f m", corridorRoute.length))
let corridorTurns = corridorRoute.turns()
check("Se detectan los dos giros de la ruta", corridorTurns.count == 2 && abs(corridorTurns[0] - 6000) < 60 && abs(corridorTurns[1] - 10000) < 60,
      corridorTurns.map { String(format: "%.0f", $0) }.joined(separator: ", "))
let located = corridorRoute.locate(corridorRoute.point(at: 7300).moved(30, bearing: 35))
check("Situar un punto en la ruta (a lo largo y de lado)", abs(located.along - 7300) < 5 && abs(located.offset - 30) < 2,
      String(format: "%.1f m / %.1f m", located.along, located.offset))

// Imagen guardada de prueba: la misma cámara que pide la app (moto al 72 % del alto).
func fakeShot(_ here: GeoPoint, heading h: Double, style: String, anchor: Double, visible: Double = corridorVisible) -> CorridorEntry? {
    let v = visible
    let ahead = (MapCorridor.puckY - 0.5) * v
    let c = here.moved(ahead, bearing: h)
    func cam(_ g: GeoPoint) -> CGPoint {
        let dy = (g.lat - c.lat) * 110_574.0
        let dx = (g.lon - c.lon) * 111_320.0 * cos(c.lat * .pi / 180)
        let r = h * .pi / 180
        let forward = dx * sin(r) + dy * cos(r)
        let right = dx * cos(r) - dy * sin(r)
        return CGPoint(x: 0.5 + right / (v * 2), y: 0.5 - forward / v)
    }
    let pts = [c.moved(60, bearing: h).moved(60, bearing: h + 90), c.moved(60, bearing: h).moved(60, bearing: h - 90),
               c.moved(-60, bearing: h).moved(60, bearing: h - 90), c.moved(-60, bearing: h).moved(60, bearing: h + 90)]
    guard let b = MapBase(image: nil, data: Data(repeating: 7, count: 90_000), pixelWidth: 800, pixelHeight: 400, center: c,
                          heading: h, pitch: 0, night: style == "noche", live: false, anchor: anchor, created: 0,
                          styleKey: style, samples: pts.map { ($0, cam($0)) }) else { return nil }
    return CorridorEntry(base: b, anchor: anchor, ahead: ahead)
}

// Simula lo que hace la app con el iPhone desbloqueado: pedir lo que falta hasta completar.
func fillCorridor(_ route: RoutePath, from progress: Double, existing: [CorridorEntry], nightAfter: Double = .infinity, capacity: Int = 400) -> [CorridorEntry] {
    var list = existing
    let turns = route.turns()
    let horizon = CorridorPlanner.horizon(remaining: route.length - progress, capacity: capacity, step: corridorStep)
    let anchors = CorridorPlanner.anchors(route: route, from: progress, to: progress + horizon, step: corridorStep, turns: turns)
    for _ in 0..<20 {
        let wanted = CorridorPlanner.missing(anchors: anchors, route: route, existing: list, inFlight: [],
                                             night: { $0 > nightAfter }, styleKey: { $0 ? "noche" : "dia" },
                                             northUp: false, step: corridorStep, limit: 50)
        if wanted.isEmpty { break }
        for r in wanted {
            if let e = fakeShot(r.here, heading: r.heading, style: r.night ? "noche" : "dia", anchor: r.anchor) { list.append(e) }
        }
        list.sort { $0.anchor < $1.anchor }
    }
    return list
}

let fullCorridor = fillCorridor(corridorRoute, from: 0, existing: [])
let fullCoverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: fullCorridor, northUp: false)
check("Ruta de 15 km guardada entera, sin huecos (antes: unos 8 km como máximo)",
      fullCoverage.continuous >= corridorRoute.length - 30 && fullCoverage.gaps == 0,
      String(format: "%.1f km seguidos, %d imágenes, %d huecos", fullCoverage.continuous / 1000, fullCorridor.count, fullCoverage.gaps))
check("Las curvas tienen su imagen orientada a la calle nueva",
      corridorTurns.allSatisfy { t in fullCorridor.contains { abs($0.anchor - (t + 15)) < 1 && headingGap($0.base.heading, corridorRoute.bearing(at: t + 55, span: 60)) < 5 } })
let again = CorridorPlanner.missing(anchors: CorridorPlanner.anchors(route: corridorRoute, from: 0, to: corridorRoute.length, step: corridorStep, turns: corridorTurns),
                                    route: corridorRoute, existing: fullCorridor, inFlight: [], night: { _ in false },
                                    styleKey: { $0 ? "noche" : "dia" }, northUp: false, step: corridorStep, limit: 50)
check("No se vuelve a pedir lo que ya está guardado", again.isEmpty, "\(again.count) repetidas")
let pending = CorridorPlanner.missing(anchors: [100, 400, 700], route: corridorRoute, existing: [], inFlight: [400],
                                      night: { _ in false }, styleKey: { _ in "dia" }, northUp: false, step: corridorStep, limit: 5)
check("Lo que ya está pedido no se pide dos veces y se empieza por lo más cercano", pending.map { $0.anchor } == [100, 700])
let mb = Double(fullCorridor.reduce(0) { $0 + $1.bytes }) / 1_048_576
check("La memoria del mapa guardado queda acotada (15 km en menos de 20 MB)", mb < 20, String(format: "%.1f MB", mb))

// Memoria limitada: solo se guarda lo que cabe, lo más cercano primero.
let smallCorridor = fillCorridor(corridorRoute, from: 0, existing: [], capacity: 20)
check("Con memoria para 20 imágenes se guarda el tramo más cercano",
      smallCorridor.count <= 24 && smallCorridor.allSatisfy { $0.anchor < 20 * corridorStep + 100 }, "\(smallCorridor.count) imágenes")
let trimmed = CorridorPlanner.trim(fullCorridor, progress: 5000, capacity: 30)
check("Al pasar de largo y con poca memoria se sueltan las de atrás y las más lejanas",
      trimmed.count == 30 && trimmed.allSatisfy { $0.anchor >= 4600 && $0.anchor < 5000 + 31 * corridorStep })

// Huecos: sin imágenes entre 4 y 5 km la cobertura seguida se corta ahí.
let holed = fullCorridor.filter { $0.anchor < 3900 || $0.anchor > 5100 }
let holedCoverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: holed, northUp: false)
check("Se detecta el tramo sin imagen", holedCoverage.gaps == 1 && holedCoverage.continuous > 3800 && holedCoverage.continuous < 4400,
      String(format: "seguido %.1f km, %d huecos", holedCoverage.continuous / 1000, holedCoverage.gaps))
// 0.6.3: los km guardados no saltan al avanzar unos metros (antes los puntos de revisión se
// movían con la moto y un hueco pequeño aparecía o no según el instante).
var holedEnds: [Double] = []
for offset in stride(from: 0.0, through: 210.0, by: 7.0) {
    holedEnds.append(500 + offset + CorridorCoverage.scan(route: corridorRoute, from: 500 + offset, to: corridorRoute.length, entries: holed, northUp: false).continuous)
}
let holedSpread = (holedEnds.max() ?? 0) - (holedEnds.min() ?? 0)
check("Cobertura estable: al avanzar, el final del mapa guardado no salta", holedSpread <= 30,
      String(format: "el final se mueve %.0f m en 31 posiciones", holedSpread))

// Recálculo: la ruta nueva comparte los primeros 6 km y luego va por otro lado.
let rerouted = RoutePath(points: legs(corridorStart, [(6000, 35), (5000, 300)]))
let kept = CorridorPlanner.retain(fullCorridor, on: rerouted, northUp: false)
let keptFirstLeg = kept.filter { $0.anchor < 5900 }.count
let firstLeg = fullCorridor.filter { $0.anchor < 5900 }.count
check("Al recalcular se conservan las imágenes que siguen sobre la ruta nueva (antes se borraban todas)",
      keptFirstLeg >= firstLeg - 1 && kept.allSatisfy { $0.anchor < 6200 }, "\(kept.count) de \(fullCorridor.count)")
let refilled = fillCorridor(rerouted, from: 2000, existing: kept)
let refilledCoverage = CorridorCoverage.scan(route: rerouted, from: 2000, to: rerouted.length, entries: refilled, northUp: false)
check("Tras recalcular, solo se pide el tramo nuevo", refilled.count - kept.count < 45 && refilledCoverage.gaps == 0,
      "\(refilled.count - kept.count) nuevas")

// Recálculo desde donde está la moto (lo normal): la ruta nueva empieza ahí, así que su
// rejilla no coincide con la de antes. Lo conservado tiene que contar igual.
let cutAt = 2037.0
let fromHere = RoutePath(points: legs(corridorRoute.point(at: cutAt), [(6000 - cutAt, 35), (4000, 125), (5000, 35)]))
let keptHere = CorridorPlanner.retain(fullCorridor, on: fromHere, northUp: false)
let fromHereAnchors = CorridorPlanner.anchors(route: fromHere, from: 0, to: fromHere.length, step: corridorStep, turns: fromHere.turns())
let askedAgain = CorridorPlanner.missing(anchors: fromHereAnchors, route: fromHere, existing: keptHere, inFlight: [],
                                         night: { _ in false }, styleKey: { _ in "dia" }, northUp: false, step: corridorStep, limit: 500)
let fromHereCoverage = CorridorCoverage.scan(route: fromHere, from: 0, to: fromHere.length, entries: keptHere, northUp: false)
check("Recalculando desde la posición actual no se vuelve a pedir lo que ya se tiene (antes: casi todo otra vez)",
      keptHere.count > 60 && askedAgain.count <= 2 && fromHereCoverage.gaps == 0,
      "\(keptHere.count) conservadas, \(askedAgain.count) pedidas de nuevo")
let planStartMissing = Date()
for _ in 0..<10 {
    _ = CorridorPlanner.missing(anchors: fromHereAnchors, route: fromHere, existing: keptHere, inFlight: [],
                                night: { _ in false }, styleKey: { _ in "dia" }, northUp: false, step: corridorStep, limit: 2)
}
let missingMs = Date().timeIntervalSince(planStartMissing) * 1000 / 10
check("Decidir qué pedir (13 km ya guardados) tarda poco", missingMs < 40, String(format: "%.1f ms", missingMs))

// Con la moto avanzando, como la app: cada 0,25 s se mira qué falta, dos imágenes a la vez,
// y la calibración de Apple mueve un poco el alto visible con cada imagen.
func driveCorridor(_ route: RoutePath, seconds: Double, speed: Double, imageSeconds: Double, parallel: Int = 2, capacity: Int = 400)
    -> (entries: [CorridorEntry], requests: Int, repeated: Int, progress: Double) {
    let routeTurns = route.turns()
    var list: [CorridorEntry] = []
    var flying: [(request: CorridorRequest, ready: Double)] = []
    var asked: [Double] = []
    var requests = 0
    var repeated = 0
    var step = 0.0
    var progress = 0.0
    var t = 0.0
    var tick = 0
    while t < seconds {
        tick += 1
        step = CorridorPlanner.stableStep(current: step, visible: corridorVisible * (1 + 0.08 * sin(Double(tick) * 0.7)))
        for f in flying where f.ready <= t {
            if let e = fakeShot(f.request.here, heading: f.request.heading, style: "dia", anchor: f.request.anchor) { list.append(e) }
        }
        flying.removeAll { $0.ready <= t }
        list.sort { $0.anchor < $1.anchor }
        list = CorridorPlanner.trim(list, progress: progress, capacity: capacity)
        let free = parallel - flying.count
        if free > 0 {
            let horizon = CorridorPlanner.horizon(remaining: route.length - progress, capacity: capacity, step: step)
            let anchors = CorridorPlanner.anchors(route: route, from: progress, to: progress + horizon, step: step, turns: routeTurns)
            let wanted = CorridorPlanner.missing(anchors: anchors, route: route, existing: list, inFlight: flying.map { $0.request.anchor },
                                                 night: { _ in false }, styleKey: { _ in "dia" }, northUp: false, step: step, limit: free)
            for r in wanted {
                // Repetida: un punto de la rejilla que ya se había pedido (las de los giros
                // son aparte y pueden caer cerca de uno de la rejilla).
                if !routeTurns.contains(where: { abs($0 + 15 - r.anchor) < 1 }) {
                    if asked.contains(where: { abs($0 - r.anchor) < step * 0.5 }) { repeated += 1 }
                    asked.append(r.anchor)
                }
                flying.append((r, t + imageSeconds))
                requests += 1
            }
        }
        progress += speed * 0.25
        t += 0.25
    }
    return (list, requests, repeated, progress)
}
// Como la prueba del simulador: 60 s con la app abierta, 12 m/s y unos 4,5 s por imagen.
// Antes quedaban 0,8 km seguidos (registro de la prueba en segundo plano); ahora cada imagen
// nueva amplía el mapa por delante.
let simDrive = driveCorridor(corridorRoute, seconds: 60, speed: 12, imageSeconds: 4.5)
let simCoverage = CorridorCoverage.scan(route: corridorRoute, from: simDrive.progress, to: corridorRoute.length, entries: simDrive.entries, northUp: false)
check("Avanzando, cada imagen nueva amplía el mapa por delante (60 s como en el simulador)",
      simCoverage.continuous > 3500 && simDrive.repeated == 0,
      String(format: "%.1f km seguidos con %d peticiones, %d repetidas", simCoverage.continuous / 1000, simDrive.requests, simDrive.repeated))
// Con imágenes más rápidas (iPhone real, unos 2 s), en 4 minutos queda guardada toda la ruta.
let longDrive = driveCorridor(corridorRoute, seconds: 240, speed: 12, imageSeconds: 2)
let longCoverage = CorridorCoverage.scan(route: corridorRoute, from: longDrive.progress, to: corridorRoute.length, entries: longDrive.entries, northUp: false)
check("Avanzando 4 minutos se guarda toda la ruta que queda, sin huecos ni repetidas",
      longCoverage.continuous >= corridorRoute.length - longDrive.progress - 30 && longCoverage.gaps == 0 && longDrive.repeated == 0
      && longDrive.requests <= Int(corridorRoute.length / corridorStep) + 6,
      String(format: "%.1f de %.1f km, %d peticiones, %d repetidas", longCoverage.continuous / 1000,
             (corridorRoute.length - longDrive.progress) / 1000, longDrive.requests, longDrive.repeated))
check("La separación no cambia por pequeñas variaciones de la calibración",
      CorridorPlanner.stableStep(current: 177, visible: corridorVisible * 1.08) == 177
      && CorridorPlanner.stableStep(current: 177, visible: corridorVisible * 1.4) > 230)

// Qué imagen usa cada fotograma.
func poseAt(_ route: RoutePath, _ d: Double) -> MapPose {
    MapPose(here: route.point(at: d), heading: route.bearing(at: d, span: 18), speed: 12, progress: d, toTurn: nil)
}
let choice1 = MapChooser.choose(live: nil, entries: fullCorridor, pose: poseAt(corridorRoute, 2500), wantedStyle: "dia",
                                now: 100, preview: false, northUp: false)
check("iPhone bloqueado: se usa una imagen guardada", choice1.base != nil && choice1.source == .cached)
let mixed = fillCorridor(corridorRoute, from: 0, existing: [], nightAfter: 9000)
let nightChoice = MapChooser.choose(live: nil, entries: mixed, pose: poseAt(corridorRoute, 12000), wantedStyle: "noche",
                                    now: 100, preview: false, northUp: false)
check("Lo que se recorrerá de noche ya se guarda en oscuro", nightChoice.source == .cached && nightChoice.base?.styleKey == "noche"
      && mixed.contains { $0.base.styleKey == "dia" } && mixed.contains { $0.base.styleKey == "noche" })
let both = fullCorridor + fillCorridor(corridorRoute, from: 0, existing: [], nightAfter: -1)
let rightTheme = MapChooser.choose(live: nil, entries: both, pose: poseAt(corridorRoute, 3000), wantedStyle: "noche",
                                   now: 100, preview: false, northUp: false)
check("Con las dos versiones guardadas gana siempre el tema correcto", rightTheme.base?.styleKey == "noche" && rightTheme.source == .cached)
let onlyDay = MapChooser.choose(live: nil, entries: fullCorridor, pose: poseAt(corridorRoute, 3000), wantedStyle: "noche",
                                now: 100, preview: false, northUp: false)
check("Si solo hay del otro tema, se usa y se marca (mejor que un hueco)", onlyDay.source == .cachedOtherStyle)
let noImage = MapChooser.choose(live: nil, entries: [], pose: poseAt(corridorRoute, 3000), wantedStyle: "dia",
                                now: 100, preview: false, northUp: false)
check("Sin imagen que sirva: mapa simple, sin inventar calles", noImage.base == nil && noImage.source == .none)
if let liveShot = fakeShot(corridorRoute.point(at: 3000), heading: corridorRoute.bearing(at: 3040, span: 60), style: "dia", anchor: -1) {
    let fresh = MapChooser.choose(live: liveShot.base, entries: fullCorridor, pose: poseAt(corridorRoute, 3000), wantedStyle: "dia",
                                  now: 10, preview: false, northUp: false)
    let old = MapChooser.choose(live: liveShot.base, entries: [], pose: poseAt(corridorRoute, 3010), wantedStyle: "dia",
                                now: 100, preview: false, northUp: false)
    check("La imagen en vivo reciente manda; una vieja solo como último recurso", fresh.source == .live && old.source == .liveOld)
}

// Spotify: una portada que llega tarde no se queda con otra canción.
var gate = ArtworkGate()
let firstSong = gate.begin("cancion-1")
let repeated = gate.begin("cancion-1")
let secondSong = gate.begin("cancion-2")
check("Portadas: solo vale la de la canción que suena", firstSong && !repeated && secondSong
      && !gate.accepts("cancion-1") && gate.accepts("cancion-2") && !gate.accepts(""))

// Rendimiento de la planificación (se hace con la app abierta, en el hilo principal).
let planStart = Date()
for _ in 0..<20 {
    _ = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: fullCorridor, northUp: false)
}
let scanMs = Date().timeIntervalSince(planStart) * 1000 / 20
check("Revisar la cobertura de 15 km tarda poco", scanMs < 60, String(format: "%.1f ms", scanMs))

// 10c-bis. Versión 0.6.5: el guardado no debe quedarse parado.
// (1) Curvas cerradas que no cuentan como giro (radio de 90 a 200 m): se comprobó que la rejilla
// las cubre entera; no eran la causa. Queda como prueba de que no empeora.
func winding(_ start: GeoPoint, _ parts: [(length: Double, turn: Double)]) -> [GeoPoint] {
    var pts = [start]
    var here = start
    var bearing = 20.0
    for part in parts {
        let n = max(1, Int(part.length / 10))
        for _ in 0..<n {
            bearing += part.turn / Double(n)
            here = here.moved(part.length / Double(n), bearing: bearing)
            pts.append(here)
        }
    }
    return pts
}
let curvy = RoutePath(points: winding(corridorStart, [(800, 0), (300, 150), (600, 0), (320, -130), (500, 0),
                                                      (180, 100), (180, -100), (400, 0), (260, 160), (700, 0)]))
// Lo que hace la app desde la 0.6.5: rejilla + huecos, lo más cercano primero, 3 a la vez.
func fillWithGaps(_ route: RoutePath, start: [CorridorEntry] = [], shortAt: [Double] = []) -> (list: [CorridorEntry], fills: Int, rounds: Int) {
    var list = start
    var attempts: [Int: Int] = [:]
    var fills = 0
    var rounds = 0
    let horizon = CorridorPlanner.horizon(remaining: route.length, capacity: 400, step: corridorStep)
    let anchors = CorridorPlanner.anchors(route: route, from: 0, to: horizon, step: corridorStep, turns: route.turns())
    for _ in 0..<80 {
        let grid = CorridorPlanner.missing(anchors: anchors, route: route, existing: list, inFlight: [],
                                           night: { _ in false }, styleKey: { $0 ? "noche" : "dia" },
                                           northUp: false, step: corridorStep, limit: 3)
        let extra = CorridorPlanner.gapFills(route: route, progress: 0, end: horizon, existing: list,
                                             inFlight: [], night: { _ in false },
                                             styleKey: { $0 ? "noche" : "dia" }, northUp: false,
                                             attempts: attempts, limit: 3)
        let wanted = CorridorPlanner.merge(grid, extra, limit: 3)
        for f in wanted where extra.contains(f) {
            attempts[Int(f.anchor / 25), default: 0] += 1
            fills += 1
        }
        if wanted.isEmpty { break }
        rounds += 1
        for r in wanted {
            // Las de `shortAt` llegan cubriendo menos terreno (otra escala).
            let short = shortAt.contains { abs($0 - r.anchor) < 1 }
            if let e = fakeShot(r.here, heading: r.heading, style: "dia", anchor: r.anchor,
                                visible: short ? corridorVisible * 0.3 : corridorVisible) { list.append(e) }
        }
        list.sort { $0.anchor < $1.anchor }
    }
    return (list, fills, rounds)
}
let curvyTurns = curvy.turns()
let curvyGrid = fillCorridor(curvy, from: 0, existing: [])
let curvyGridCoverage = CorridorCoverage.scan(route: curvy, from: 0, to: curvy.length, entries: curvyGrid, northUp: false)
let curvyNew = fillWithGaps(curvy)
let curvyNewCoverage = CorridorCoverage.scan(route: curvy, from: 0, to: curvy.length, entries: curvyNew.list, northUp: false)
check("Ruta de curvas cerradas de prueba (4,2 km, ninguna cuenta como giro)",
      abs(curvy.length - 4240) < 30 && curvyTurns.isEmpty, String(format: "%.0f m, %d giros", curvy.length, curvyTurns.count))
check("Curvas cerradas: la rejilla las guarda enteras (no eran la causa de quedarse parado)",
      curvyGridCoverage.continuous >= curvy.length - 30 && curvyGridCoverage.gaps == 0,
      String(format: "%.1f de %.1f km seguidos, %d imágenes", curvyGridCoverage.continuous / 1000, curvy.length / 1000, curvyGrid.count))
check("0.6.5: en curvas y en la ruta de 15 km no se pide ninguna imagen extra",
      curvyNew.fills == 0 && fillWithGaps(corridorRoute).fills == 0 && curvyNewCoverage.continuous >= curvy.length - 30,
      "\(curvyNew.fills) extra en curvas")
// (2) Una imagen que llega cubriendo menos de lo previsto deja un hueco que la rejilla ya no vuelve
// a pedir (su ancla ya tiene imagen): así el guardado se quedaría parado en ese punto.
let shortAnchors = CorridorPlanner.anchors(route: corridorRoute, from: 0, to: corridorRoute.length, step: corridorStep, turns: corridorTurns)
    .filter { $0 > 2900 && $0 < 3300 }
var shortList = fullCorridor.filter { e in !shortAnchors.contains { abs($0 - e.anchor) < 1 } }
for a in shortAnchors {
    if let e = fakeShot(corridorRoute.point(at: a), heading: CorridorPlanner.heading(route: corridorRoute, at: a, northUp: false),
                        style: "dia", anchor: a, visible: corridorVisible * 0.3) { shortList.append(e) }
}
shortList.sort { $0.anchor < $1.anchor }
let shortCoverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: shortList, northUp: false)
let shortGrid = CorridorPlanner.missing(anchors: CorridorPlanner.anchors(route: corridorRoute, from: 0, to: corridorRoute.length, step: corridorStep, turns: corridorTurns),
                                        route: corridorRoute, existing: shortList, inFlight: [], night: { _ in false },
                                        styleKey: { $0 ? "noche" : "dia" }, northUp: false, step: corridorStep, limit: 50)
check("Si una imagen cubre menos de lo previsto queda un hueco que la rejilla no vuelve a pedir (se quedaría parado)",
      shortCoverage.gaps >= 1 && shortCoverage.continuous < 3400 && shortGrid.isEmpty,
      String(format: "seguido %.1f km, %d huecos, %d pedidas por la rejilla", shortCoverage.continuous / 1000, shortCoverage.gaps, shortGrid.count))
let shortFixed = fillWithGaps(corridorRoute, start: shortList)
let shortFixedCoverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: shortFixed.list, northUp: false)
check("0.6.5: se piden imágenes justo en el hueco y la ruta queda guardada entera",
      shortFixedCoverage.continuous >= corridorRoute.length - 30 && shortFixedCoverage.gaps == 0 && shortFixed.fills > 0 && shortFixed.fills <= 6,
      String(format: "%.1f km seguidos, %d huecos, %d imágenes extra", shortFixedCoverage.continuous / 1000, shortFixedCoverage.gaps, shortFixed.fills))
let stuckAgain = CorridorPlanner.gapFills(route: corridorRoute, progress: 0, end: corridorRoute.length, existing: shortFixed.list, inFlight: [],
                                          night: { _ in false }, styleKey: { $0 ? "noche" : "dia" }, northUp: false,
                                          attempts: [:], limit: 3)
check("0.6.5: con la ruta guardada entera ya no se piden más imágenes extra", stuckAgain.isEmpty, "\(stuckAgain.count)")
let noLoop = CorridorPlanner.gapFills(route: corridorRoute, progress: 0, end: corridorRoute.length, existing: shortList, inFlight: [],
                                      night: { _ in false }, styleKey: { $0 ? "noche" : "dia" }, northUp: false,
                                      attempts: Dictionary(uniqueKeysWithValues: (0..<700).map { ($0, 2) }), limit: 3)
check("0.6.5: un hueco que no se llena tras dos intentos no se pide sin fin", noLoop.isEmpty, "\(noLoop.count)")
let notAhead = CorridorPlanner.gapFills(route: corridorRoute, progress: 0, end: corridorRoute.length,
                                        existing: fullCorridor.filter { $0.anchor < 2000 }, inFlight: [],
                                        night: { _ in false }, styleKey: { $0 ? "noche" : "dia" }, northUp: false,
                                        attempts: [:], limit: 3)
check("0.6.5: lo que la rejilla todavía no pidió no se toma por hueco", notAhead.isEmpty, "\(notAhead.count)")

// 10d. Versión 0.6.2: hora actual fija, llegada con su nombre, maniobra compacta y música completa.
let fullImage = CGRect(x: 0, y: 0, width: W, height: H)
let clockSpot = DashLayoutEngine.statusClock(in: fullImage, k: 1)
var clockProblem: String?
for mode in DashMode.allCases where DashLayout.preset(mode).template == .overlay {
    let cards = DashLayoutEngine.overlayCards(DashLayout.preset(mode).overlay, in: fullImage, k: 1)
    if cards.first(where: { $0.item == .time })?.rect != clockSpot {
        clockProblem = "\(mode.label): la hora no está en su sitio"
    } else if let hit = cards.first(where: { $0.item != .time && $0.rect.intersects(clockSpot) }) {
        clockProblem = "\(mode.label): \(hit.item) tapa la hora"
    }
}
check("Hora actual: el mismo sitio en los modos con mapa y nada encima", clockProblem == nil,
      clockProblem ?? String(format: "arriba a la derecha: x %.0f, y %.0f, %.0f×%.0f", clockSpot.minX, clockSpot.minY, clockSpot.width, clockSpot.height))

// Píxeles del color del texto dentro del sitio de la hora (blanco de noche, casi negro de día).
func clockInk(_ r: (image: CGImage?, data: [UInt8], rowBytes: Int), night: Bool) -> Int {
    var n = 0
    for y in Int(clockSpot.minY)..<Int(clockSpot.maxY) {
        for x in Int(clockSpot.minX)..<Int(clockSpot.maxX) {
            let o = y * r.rowBytes + x * 4
            let b = Int(r.data[o])
            let g = Int(r.data[o + 1])
            let rr = Int(r.data[o + 2])
            if night ? (rr > 225 && g > 225 && b > 225) : (rr < 40 && g < 45 && b < 60) { n += 1 }
        }
    }
    return n
}
var clockMissing: [String] = []
var clockRenders = 0
for mode in DashMode.allCases {
    for theme in [DashTheme.dark, .light] {
        for routeOn in [true, false] {
            var s = streetsSnapshot(.preset(mode), theme: theme)
            if !routeOn {
                s.nav.navigating = false
                s.nav.shape = nil
                s.nav.here = center.moved(90, bearing: heading + 180)
                s.nav.course = heading
            }
            clockRenders += 1
            if clockInk(pixels(s), night: theme == .dark) < 40 {
                clockMissing.append("\(mode.label) \(theme == .dark ? "oscuro" : "claro") \(routeOn ? "con" : "sin") ruta")
            }
        }
    }
}
check("La hora se ve en el mismo sitio en todos los modos, de día y de noche, con y sin ruta", clockMissing.isEmpty,
      clockMissing.isEmpty ? "\(clockRenders) composiciones" : clockMissing.joined(separator: ", "))

let etaSnap = streetsSnapshot(.preset(.gpsMusic), theme: .dark)
let etaParts = HUDFormat.tripParts(etaSnap.nav)
let etaClock = etaSnap.nav.eta.map { HUDFormat.clock($0) }
check("La llegada lleva la palabra «Llegada»; el tiempo y la distancia van aparte",
      etaParts.label == "Llegada" && etaParts.eta == etaClock?.time && etaParts.suffix == etaClock?.suffix
      && etaParts.remaining == "18 min" && etaParts.distance == "7.4 km",
      "\(etaParts.label) \(etaParts.eta) \(etaParts.suffix) | \(etaParts.remaining) | \(etaParts.distance)")
check("La hora de llegada y la hora actual son cosas distintas (7:22 y 7:04)",
      etaParts.eta != HUDFormat.clock(now).time)
var idleTrip = streetsSnapshot(.preset(.gpsMusic), theme: .dark)
idleTrip.nav.navigating = false
idleTrip.nav.shape = nil
// Sin ruta, el mapa sigue donde está la moto (como en la foto de la TFT).
idleTrip.nav.here = center.moved(90, bearing: heading + 180)
idleTrip.nav.course = heading
var idleNoTrip = idleTrip
idleNoTrip.layout.overlay.trip = false
check("Sin ruta, abajo no aparece otra hora (solo la fija de arriba)", pixels(idleTrip).data == pixels(idleNoTrip).data)

// Maniobra compacta.
let newManeuver = DashLayoutEngine.cardSize(.maneuver, OverlaySettings())
check("Maniobra compacta un 30 % más pequeña por lado (antes 284×136)",
      abs(newManeuver.width / 284 - 0.7) < 0.03 && abs(newManeuver.height / 136 - 0.7) < 0.03,
      String(format: "%.0f×%.0f, %.0f %% del área de antes", newManeuver.width, newManeuver.height, newManeuver.width * newManeuver.height / (284 * 136) * 100))
var largeManeuver = OverlaySettings()
largeManeuver.maneuverSize = .large
check("La tarjeta grande de la maniobra sigue igual", DashLayoutEngine.cardSize(.maneuver, largeManeuver) == CGSize(width: 340, height: 176))
let mapMusicCards = DashLayoutEngine.overlayCards(DashLayout.preset(.gpsMusic).overlay, in: fullImage, k: 1)
let maneuverRect = mapMusicCards.first { $0.item == .maneuver }?.rect ?? .null
let musicRect = mapMusicCards.first { $0.item == .music }?.rect ?? .null
let corridor = CGRect(x: 250, y: 0, width: 280, height: 330)
check("Mapa + Música: el centro (por donde va la ruta) queda libre de tarjetas",
      maneuverRect.maxX <= 250 && musicRect.minX >= 530 && !mapMusicCards.contains { $0.rect.intersects(corridor) },
      String(format: "maniobra hasta x %.0f, música desde x %.0f", maneuverRect.maxX, musicRect.minX))
check("La tarjeta de música no crece (250×84)", musicRect.size == CGSize(width: 250, height: 84))
let streetCases: [(String, String?)] = [
    ("Da vuelta a la derecha por 7a Avenida", "7a Avenida"),
    ("En la glorieta, continúa por 10a Avenida", "10a Avenida"),
    ("Mantente a la derecha hacia 1a Calle", "1a Calle"),
    ("Toma la salida hacia CA-9 Sur", "CA-9 Sur"),
    ("Continúa por la Calzada Roosevelt", "Calzada Roosevelt"),
    ("Turn right onto 5th Ave", "5th Ave"),
    ("Gira a la izquierda", nil),
    ("Mantente por la derecha", nil),
]
let streetFails = streetCases.filter { HUDFormat.street(from: $0.0) != $0.1 }.map { "«\($0.0)» → \(HUDFormat.street(from: $0.0) ?? "nada")" }
check("La calle se saca de la indicación (el giro ya lo dice la flecha)", streetFails.isEmpty,
      streetFails.isEmpty ? "\(streetCases.count) indicaciones" : streetFails.joined(separator: "; "))

// Música completa al estilo de CarPlay.
let musicArea = fullImage.insetBy(dx: 6, dy: 6)
let musicFrame = DashLayoutEngine.frames(.preset(.music), in: musicArea, gap: 6).first?.rect ?? .null
func stageProblems(_ frame: CGRect, size: ArtworkSize) -> String? {
    guard MusicStageLayout.fits(frame, k: 1) else { return "no cabe en \(frame.size)" }
    let L = MusicStageLayout.make(frame, k: 1, artwork: true, size: size, reserve: clockSpot)
    let parts = [("cabecera", L.header), ("portada", L.artwork), ("textos", L.text), ("barra", L.progress)]
    for (i, a) in parts.enumerated() {
        if !frame.insetBy(dx: -0.5, dy: -0.5).contains(a.1) { return "\(a.0) se sale" }
        if a.1.intersects(clockSpot) { return "\(a.0) tapa la hora" }
        for b in parts[(i + 1)...] where a.1.intersects(b.1) { return "\(a.0) y \(b.0) se montan" }
    }
    return nil
}
let stageNormal = MusicStageLayout.make(musicFrame, k: 1, artwork: true, size: .normal, reserve: clockSpot)
var stageFrameNav = musicFrame
stageFrameNav.size.height -= 62 + 6
let stageNav = MusicStageLayout.make(stageFrameNav, k: 1, artwork: true, size: .normal, reserve: clockSpot)
let stageProblem = [ArtworkSize.small, .normal, .large].compactMap { stageProblems(musicFrame, size: $0) }.first
    ?? stageProblems(stageFrameNav, size: .normal)
check("Música completa: portada, textos y barra sin montarse ni tapar la hora", stageProblem == nil, stageProblem ?? "")
check("Música completa: portada grande (más del 60 % del alto de la imagen)", stageNormal.artwork.height >= 0.6 * H,
      String(format: "%.0f px; con el próximo giro abajo, %.0f px", stageNormal.artwork.height, stageNav.artwork.height))
check("Música completa: título y artista con una columna ancha y la barra casi a todo el ancho",
      stageNormal.text.width >= musicFrame.width * 0.5 && stageNormal.progress.width >= musicFrame.width * 0.9,
      String(format: "columna de %.0f px, barra de %.0f px", stageNormal.text.width, stageNormal.progress.width))

// Portada de demostración propia (no copia ninguna real): fondo violeta y una franja de neón.
func artwork256(_ draw: (CGContext) -> Void) -> CGImage? {
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
    draw(ctx)
    return ctx.makeImage()
}
let neon = artwork256 { ctx in
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = [CGColor(srgbRed: 0.24, green: 0.08, blue: 0.42, alpha: 1), CGColor(srgbRed: 0.03, green: 0.04, blue: 0.14, alpha: 1)] as CFArray
    if let g = CGGradient(colorsSpace: space, colors: bg, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 256), end: CGPoint(x: 256, y: 0), options: [])
    }
    ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.03, blue: 0.1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 72, y: 30, width: 120, height: 170))
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.25, blue: 0.72, alpha: 1))
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: 58, y: 136))
    ctx.addLine(to: CGPoint(x: 206, y: 146))
    ctx.strokePath()
    ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.8, blue: 1, alpha: 1))
    ctx.setLineWidth(4)
    ctx.move(to: CGPoint(x: 60, y: 146))
    ctx.addLine(to: CGPoint(x: 204, y: 156))
    ctx.strokePath()
}
func stageSnapshot(_ theme: DashTheme, art: CGImage?, source: String, route: Bool = false) -> DashSnapshot {
    var s = route ? streetsSnapshot(.preset(.music), theme: theme) : DashDemo.snapshot(layout: .preset(.music), theme: theme, now: now)
    if !route { s.nav.navigating = false }
    s.music.title = "Luces de la ciudad"
    s.music.artist = "Banda de ejemplo"
    s.music.album = "Ruta nocturna"
    s.music.source = source
    s.music.artwork = art
    s.music.palette = art.flatMap { ArtPalette.extract($0) }
    return s
}
func rgbAt(_ r: (image: CGImage?, data: [UInt8], rowBytes: Int), _ x: CGFloat, _ y: CGFloat) -> RGB {
    let o = Int(y) * r.rowBytes + Int(x) * 4
    return RGB(Double(r.data[o + 2]) / 255, Double(r.data[o + 1]) / 255, Double(r.data[o]) / 255)
}
var worstStage = 99.0
for theme in [DashTheme.dark, .light] {
    for art in [neon, redBlack, blue] {
        let s = stageSnapshot(theme, art: art, source: "Spotify")
        let r = pixels(s)
        let text = MusicCardColors.make(style: .dynamic, palette: s.music.palette, night: s.night, intensity: s.musicIntensity, spotify: true).text
        let t = stageNormal.text.insetBy(dx: 3, dy: 3)
        for pt in [CGPoint(x: t.minX, y: t.minY), CGPoint(x: t.maxX, y: t.minY), CGPoint(x: t.minX, y: t.maxY), CGPoint(x: t.maxX, y: t.maxY)] {
            worstStage = min(worstStage, text.contrast(with: rgbAt(r, pt.x, pt.y)))
        }
    }
}
check("Música completa: texto legible sobre el degradado de la portada (contraste ≥ 4,5)", worstStage >= 4.5,
      String(format: "peor %.1f:1", worstStage))

var tt = TrackTransition()
var songA = MusicSnapshot()
songA.available = true
songA.source = "Spotify"
songA.title = "A"
songA.artist = "X"
var songB = songA
songB.title = "B"
tt.update(old: MusicSnapshot(), new: songA, at: 0)
tt.update(old: songA, new: songB, at: 10)
let fadeMid = tt.fade(at: 10.2)
let fadeFrom = tt.from?.title
let fadeEnd = tt.fade(at: 10.5)
var songBArt = songB
songBArt.artwork = blue
tt.update(old: songB, new: songBArt, at: 20)
let artOnly = tt.fade(at: 20.1) == nil && tt.artFade(at: 20.1).map { abs($0 - 0.1 / TrackTransition.duration) < 0.01 } == true
var ttSame = TrackTransition()
var songAPlaying = songA
songAPlaying.position = 30
ttSame.update(old: songA, new: songAPlaying, at: 5)
check("Cambio de canción: fundido corto de la anterior a la nueva (menos de medio segundo)",
      fadeMid.map { abs($0 - 0.2 / TrackTransition.duration) < 0.01 } == true && fadeFrom == "A" && fadeEnd == nil)
check("Portada que llega tarde (Spotify): solo se funde la portada", artOnly)
check("Misma canción avanzando: sin transición", ttSame.fade(at: 5.1) == nil && ttSame.artFade(at: 5.1) == nil)

// Capturas de los tres cambios.
if let image = pixels(stageSnapshot(.dark, art: neon, source: "Spotify")).image { save(image, "cambio1-musica-noche") }
if let image = pixels(stageSnapshot(.light, art: blue, source: "Apple Music")).image { save(image, "cambio1-musica-dia") }
var paused = stageSnapshot(.dark, art: redBlack, source: "Apple Music")
paused.music.playing = false
if let image = pixels(paused).image { save(image, "cambio1-musica-en-pausa") }
var crossing = stageSnapshot(.dark, art: neon, source: "Spotify")
var previous = crossing.music
previous.title = "Canción anterior"
previous.artist = "Otro artista"
previous.album = ""
previous.artwork = redBlack
crossing.musicFrom = previous
crossing.musicFade = 0.7
crossing.paletteFrom = redBlack.flatMap { ArtPalette.extract($0) }
crossing.paletteFade = 0.7
if let image = pixels(crossing).image { save(image, "cambio1-musica-transicion") }
if let image = pixels(stageSnapshot(.dark, art: neon, source: "Spotify", route: true)).image { save(image, "cambio1-musica-con-ruta") }
for theme in [DashTheme.dark, .light] {
    var mm = streetsSnapshot(.preset(.gpsMusic), theme: theme)
    mm.music.artwork = neon
    mm.music.palette = neon.flatMap { ArtPalette.extract($0) }
    mm.music.source = "Spotify"
    if let image = pixels(mm).image { save(image, "cambio2-mapa-musica-\(theme == .dark ? "noche" : "dia")") }
}
if let image = pixels(idleTrip).image { save(image, "cambio2-mapa-musica-sin-ruta") }
for mode in [DashMode.gps, .gpsMusic, .split, .music] {
    if let image = pixels(streetsSnapshot(.preset(mode), theme: .dark)).image { save(image, "cambio3-hora-\(mode.rawValue)") }
}
// El fondo guardado entre fotogramas es igual que dibujarlo cada vez.
func maxDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
    var worst = 0
    for i in 0..<min(a.count, b.count) { worst = max(worst, abs(Int(a[i]) - Int(b[i]))) }
    return a.count == b.count ? worst : 255
}
HUDRenderer.cacheStageBackground = false
let stageLive = pixels(stageSnapshot(.dark, art: neon, source: "Spotify")).data
let stageLiveDay = pixels(stageSnapshot(.light, art: blue, source: "Apple Music")).data
HUDRenderer.cacheStageBackground = true
let stageCached = pixels(stageSnapshot(.dark, art: neon, source: "Spotify")).data
let stageCachedDay = pixels(stageSnapshot(.light, art: blue, source: "Apple Music")).data
let cacheDiff = max(maxDifference(stageLive, stageCached), maxDifference(stageLiveDay, stageCachedDay))
check("Música completa: el fondo guardado entre fotogramas se ve igual que dibujado cada vez", cacheDiff <= 3,
      "diferencia máxima \(cacheDiff) de 255")
let stageRenderer = HUDRenderer(width: Int(W), height: Int(H))
var stagePerf = crossing
stagePerf.musicFade = 0.3
let stageStart = Date()
for _ in 0..<50 { _ = DashPreview.image(stagePerf, now: now, renderer: stageRenderer) }
let stageMs = Date().timeIntervalSince(stageStart) * 1000 / 50
check("Música completa en plena transición: menos de 25 ms por fotograma", stageMs < 25, String(format: "%.1f ms de media en esta máquina", stageMs))
let steady = stageSnapshot(.dark, art: neon, source: "Spotify")
let steadyStart = Date()
for _ in 0..<50 { _ = DashPreview.image(steady, now: now, renderer: stageRenderer) }
let steadyMs = Date().timeIntervalSince(steadyStart) * 1000 / 50
check("Música completa sin transición (fondo reutilizado): menos de 15 ms por fotograma", steadyMs < 15,
      String(format: "%.1f ms de media en esta máquina", steadyMs))

// 10e. Versión 0.6.3: el mismo reproductor en todos los modos, maniobra compacta en las zonas
// con mapa, cobertura del mapa guardado y ningún texto cortado.

/// Dibuja como la moto y apunta cada texto con su caja (zona o tarjeta en la que va).
func render(_ s: DashSnapshot, width: Int = Int(W), height: Int = Int(H), hideText: Bool = false, hideControls: Bool = false)
    -> (px: (image: CGImage?, data: [UInt8], rowBytes: Int), marks: [HUDRenderer.TextMark], controls: [HUDRenderer.ControlMark]) {
    let renderer = HUDRenderer(width: width, height: height)
    HUDRenderer.recordText = true
    HUDRenderer.hideText = hideText
    HUDRenderer.hideControls = hideControls
    defer {
        HUDRenderer.recordText = false
        HUDRenderer.hideText = false
        HUDRenderer.hideControls = false
    }
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    var image: CGImage?
    data.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        renderer.drawDashboard(s, now: now, in: ctx)
        image = ctx.makeImage()
    }
    return ((image, data, width * 4), renderer.textMarks, renderer.controlMarks)
}

/// Textos que se salen de la imagen o de su zona o tarjeta (también por las esquinas
/// redondeadas), que se montan entre sí o que caen encima de la hora actual.
func textProblems(_ marks: [HUDRenderer.TextMark], width: CGFloat = W, height: CGFloat = H, clock: CGRect?) -> [String] {
    var out: [String] = []
    let image = CGRect(x: 0, y: 0, width: width, height: height)
    let shown = marks.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.rect.width > 0.5 }
    for m in shown {
        let r = m.rect.insetBy(dx: 0.5, dy: 0.5)
        if !image.contains(r) {
            out.append("«\(m.text)» se sale de la imagen")
            continue
        }
        if !m.box.insetBy(dx: -0.5, dy: -0.5).contains(r) {
            out.append("«\(m.text)» se sale de su zona o tarjeta")
            continue
        }
        let rad = min(14 * width / 800, m.box.height / 2, m.box.width / 2)
        let b = m.box
        let corners: [(CGPoint, CGPoint, Bool)] = [
            (CGPoint(x: r.minX, y: r.minY), CGPoint(x: b.minX + rad, y: b.minY + rad), r.minX < b.minX + rad && r.minY < b.minY + rad),
            (CGPoint(x: r.maxX, y: r.minY), CGPoint(x: b.maxX - rad, y: b.minY + rad), r.maxX > b.maxX - rad && r.minY < b.minY + rad),
            (CGPoint(x: r.minX, y: r.maxY), CGPoint(x: b.minX + rad, y: b.maxY - rad), r.minX < b.minX + rad && r.maxY > b.maxY - rad),
            (CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: b.maxX - rad, y: b.maxY - rad), r.maxX > b.maxX - rad && r.maxY > b.maxY - rad),
        ]
        if corners.contains(where: { $0.2 && hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) > rad + 0.5 }) {
            out.append("«\(m.text)» cortado por la esquina redondeada")
        }
        if let c = clock, r.intersects(c), !c.insetBy(dx: -1, dy: -1).contains(r) {
            out.append("«\(m.text)» tapa la hora")
        }
    }
    for i in shown.indices {
        for j in shown.indices where j > i {
            if shown[i].rect.insetBy(dx: 0.5, dy: 0.5).intersects(shown[j].rect.insetBy(dx: 0.5, dy: 0.5)) {
                out.append("«\(shown[i].text)» y «\(shown[j].text)» se montan")
            }
        }
    }
    return out
}

/// Datos como los de un viaje real (sin la etiqueta de demostración).
func musicSnap(_ layout: DashLayout, _ theme: DashTheme, art: CGImage?, source: String = "Spotify", route: Bool = true) -> DashSnapshot {
    var s = streetsSnapshot(layout, theme: theme)
    s.demo = false
    s.music.title = "Luces de la ciudad"
    s.music.artist = "Banda de ejemplo"
    s.music.album = "Ruta nocturna"
    s.music.source = source
    s.music.artwork = art
    s.music.palette = art.flatMap { ArtPalette.extract($0) }
    if !route {
        s.nav.navigating = false
        s.nav.shape = nil
        s.nav.here = center.moved(90, bearing: heading + 180)
        s.nav.course = heading
    }
    return s
}

// Las formas del reproductor según el sitio.
let zoneArea = fullImage.insetBy(dx: 6, dy: 6)
var stripArea = zoneArea
stripArea.size.height -= 62 + 6
func musicZone(_ layout: DashLayout, area: CGRect = zoneArea) -> CGRect? {
    DashLayoutEngine.frames(layout, in: area, gap: 6).first { $0.module == .music }?.rect
}
func musicCard(_ o: OverlaySettings) -> CGRect? {
    DashLayoutEngine.overlayCards(o, in: fullImage, k: 1).first { $0.item == .music }?.rect
}
var largeMusic = DashLayout.preset(.gpsMusic).overlay
largeMusic.musicSize = .large
let largeMusicLayout = DashLayout.overlay(largeMusic)
let sideLayout = DashLayout(template: .mainSide, slots: [.nav, .music, .notices], split: 0.6)
let playerCases: [(name: String, rect: CGRect?, card: CardSize?, style: MusicPlayerStyle)] = [
    ("Música sola", musicZone(.preset(.music)), nil, .stage),
    ("Dividida", musicZone(.preset(.split)), nil, .column),
    ("Música + Avisos", musicZone(.preset(.musicNotices)), nil, .column),
    ("Música + Avisos con ruta", musicZone(.preset(.musicNotices), area: stripArea), nil, .row),
    ("Nav + Música", musicCard(DashLayout.preset(.gpsMusic).overlay), .compact, .row),
    ("Completo", musicCard(DashLayout.preset(.full).overlay), .compact, .row),
    ("Tarjeta grande", musicCard(largeMusic), .large, .row),
    ("Principal + 2 (zona lateral)", musicZone(sideLayout), nil, .row),
]
func playerLayout(_ r: CGRect, _ card: CardSize?) -> MusicPlayerLayout {
    MusicPlayerLayout.make(r, k: 1, artwork: true, size: .normal, reserve: card == nil ? clockSpot : nil, card: card)
}
var styleProblems: [String] = []
var geometryProblems: [String] = []
for pc in playerCases {
    guard let r = pc.rect else {
        styleProblems.append("\(pc.name): sin zona")
        continue
    }
    let L = playerLayout(r, pc.card)
    if L.style != pc.style { styleProblems.append("\(pc.name): \(L.style.rawValue) en vez de \(pc.style.rawValue)") }
    var parts: [(String, CGRect)] = [("portada", L.artwork), ("textos", L.text), ("barra", L.progress), ("botones", L.transport.bounds)]
    if !L.header.isEmpty { parts.append(("cabecera", L.header)) }
    for (i, a) in parts.enumerated() {
        if !r.insetBy(dx: -0.5, dy: -0.5).contains(a.1) { geometryProblems.append("\(pc.name): \(a.0) se sale") }
        if pc.card == nil && a.1.intersects(clockSpot) { geometryProblems.append("\(pc.name): \(a.0) tapa la hora") }
        for b in parts[(i + 1)...] where a.1.intersects(b.1) { geometryProblems.append("\(pc.name): \(a.0) y \(b.0) se montan") }
    }
}
check("Música: el mismo reproductor en cada modo, con la forma que cabe", styleProblems.isEmpty,
      styleProblems.isEmpty ? playerCases.map { "\($0.name): \($0.style.rawValue)" }.joined(separator: ", ") : styleProblems.joined(separator: "; "))
check("Música: portada, textos, botones y barra dentro de su sitio, sin montarse ni tapar la hora", geometryProblems.isEmpty, geometryProblems.joined(separator: "; "))
func artSide(_ r: CGRect?, _ card: CardSize?) -> CGFloat { r.map { playerLayout($0, card).artwork.width } ?? 0 }
let artSplit = artSide(musicZone(.preset(.split)), nil)
let artMN = artSide(musicZone(.preset(.musicNotices)), nil)
let artMNRoute = artSide(musicZone(.preset(.musicNotices), area: stripArea), nil)
let artCard = artSide(musicCard(DashLayout.preset(.gpsMusic).overlay), .compact)
let artLarge = artSide(musicCard(largeMusic), .large)
// 0.6.4: en la columna, los botones ocupan algo más que el estado que reemplazan.
check("Música: portada proporcional al espacio (Dividida al menos 160 px; las tarjetas, como en la 0.6.3)",
      artSplit >= 160 && artMN >= 150 && artMNRoute >= 150 && artCard == 64 && artLarge == 100,
      String(format: "Dividida %.0f px, Música + Avisos %.0f (con ruta %.0f), tarjeta compacta %.0f, grande %.0f", artSplit, artMN, artMNRoute, artCard, artLarge))

// Las mismas piezas en todas las formas: fondo con los colores de la portada (el degradado de
// MusicCardColors), resplandor detrás de la portada, texto legible y estado.
let playerSnaps: [(name: String, layout: DashLayout, area: CGRect, rect: CGRect?, card: CardSize?)] = [
    ("Música sola", .preset(.music), zoneArea, musicZone(.preset(.music)), nil),
    ("Dividida", .preset(.split), zoneArea, musicZone(.preset(.split)), nil),
    ("Música + Avisos", .preset(.musicNotices), zoneArea, musicZone(.preset(.musicNotices)), nil),
    ("Nav + Música", .preset(.gpsMusic), zoneArea, musicCard(DashLayout.preset(.gpsMusic).overlay), .compact),
    ("Completo", .preset(.full), zoneArea, musicCard(DashLayout.preset(.full).overlay), .compact),
    ("Tarjeta grande", largeMusicLayout, zoneArea, musicCard(largeMusic), .large),
    ("Principal + 2", sideLayout, zoneArea, musicZone(sideLayout), nil),
]
func colorDistance(_ a: RGB, _ b: RGB) -> Double {
    ((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)).squareRoot()
}
func gradientAt(_ c: MusicCardColors, _ r: CGRect, _ q: CGPoint) -> RGB {
    let t = ((q.x - r.minX) * r.width + (q.y - r.minY) * r.height) / (r.width * r.width + r.height * r.height)
    return c.top.mixed(with: c.bottom, Double(max(0, min(1, t))))
}
var worstText = 99.0
var worstSecondary = 99.0
var worstText2 = ""
var backgroundProblems: [String] = []
var glowProblems: [String] = []
for ps in playerSnaps {
    // Con ruta, los diseños sin mapa llevan la franja del próximo giro abajo: la zona de la
    // música es la que queda encima (antes se medía la zona entera y el punto caía en la franja).
    guard let r = ps.card != nil || ps.layout.showsRoute ? ps.rect : musicZone(ps.layout, area: stripArea) else { continue }
    for theme in [DashTheme.dark, .light] {
        for (artName, art) in [("neón", neon), ("roja", redBlack), ("azul", blue)] {
            let s = musicSnap(ps.layout, theme, art: art)
            let shown = render(s)
            let bare = render(s, hideText: true).px
            let colorsNow = MusicCardColors.make(style: .dynamic, palette: s.music.palette, night: s.night, intensity: s.musicIntensity, spotify: true)
            for m in shown.marks {
                let primary = [s.music.title, s.music.artist].contains(m.text)
                let secondary = m.text == s.music.album || m.text == "1:13" || m.text == "3:34"
                guard primary || secondary, r.contains(m.rect) else { continue }
                let q = m.rect.insetBy(dx: 1, dy: 1)
                for pt in [CGPoint(x: q.minX, y: q.minY), CGPoint(x: q.maxX, y: q.minY), CGPoint(x: q.minX, y: q.maxY),
                           CGPoint(x: q.maxX, y: q.maxY), CGPoint(x: q.midX, y: q.midY)] {
                    let bg = rgbAt(bare, pt.x, pt.y)
                    let ink = primary ? colorsNow.text : colorsNow.secondary
                    let value = ink.contrast(with: bg)
                    if primary {
                        if value < worstText {
                            worstText = value
                            worstText2 = "\(ps.name) \(theme.rawValue) \(artName) «\(m.text)»"
                        }
                    } else {
                        worstSecondary = min(worstSecondary, value)
                    }
                }
            }
            let L = playerLayout(r, ps.card)
            // Lejos de la portada el fondo es el degradado de la portada.
            let far: CGPoint
            switch L.style {
            case .stage: far = CGPoint(x: r.minX + 8, y: r.maxY - 8)
            case .column: far = CGPoint(x: r.minX + 6, y: r.maxY - 6)
            case .row: far = CGPoint(x: r.maxX - 8, y: r.maxY - 8)
            }
            // 0.6.4: el fondo lleva además la luz de la portada: tiene que estar más cerca de los
            // colores de su portada que de los de cualquiera de las otras dos.
            let got = rgbAt(bare, far.x, far.y)
            var own = 9.0
            var other = 9.0
            for (otherName, otherArt) in [("neón", neon), ("roja", redBlack), ("azul", blue)] {
                let oc = MusicCardColors.make(style: .dynamic, palette: otherArt.flatMap { ArtPalette.extract($0) }, night: s.night,
                                              intensity: s.musicIntensity, spotify: true)
                let d = colorDistance(got, gradientAt(oc, r, far))
                if otherName == artName { own = d } else { other = min(other, d) }
            }
            if own >= other || own > 0.25 {
                backgroundProblems.append(String(format: "%@ %@ %@: %.2f (otra portada %.2f)", ps.name, theme.rawValue, artName, own, other))
            }
            // De noche se ve el resplandor junto a la portada (más claro que lejos de ella).
            if theme == .dark && L.artwork.width > 0 {
                let near = L.style == .row ? CGPoint(x: L.artwork.midX, y: L.artwork.minY - 5) : CGPoint(x: L.artwork.minX - 8, y: L.artwork.midY)
                if L.style != .row || r.minY < near.y - 1 {
                    if rgbAt(bare, near.x, near.y).luminance <= got.luminance * 0.98 { glowProblems.append("\(ps.name) \(artName)") }
                }
            }
        }
    }
}
check("Música: en todas las formas el fondo tiene los colores y la luz de su portada", backgroundProblems.isEmpty,
      backgroundProblems.isEmpty ? "\(playerSnaps.count) formas, 3 portadas, día y noche" : backgroundProblems.joined(separator: "; "))
check("Música: de noche se ve el resplandor de la portada en todas las formas", glowProblems.isEmpty, glowProblems.joined(separator: ", "))
check("Música: título y artista legibles en todas las formas (contraste ≥ 4,5)", worstText >= 4.5,
      String(format: "peor %.1f:1 (%@)", worstText, worstText2))
check("Música: álbum y tiempos legibles (contraste ≥ 3)", worstSecondary >= 3, String(format: "peor %.1f:1", worstSecondary))
var pausedCard = musicSnap(.preset(.gpsMusic), .dark, art: neon)
pausedCard.music.playing = false
var pausedColumn = musicSnap(.preset(.split), .dark, art: neon)
pausedColumn.music.playing = false
check("Música en pausa: el botón central pasa a ▶ (columna y tarjeta) y nada se corta",
      render(pausedColumn).controls.contains { $0.kind == "reproducir" } && render(pausedCard).controls.contains { $0.kind == "reproducir" }
      && textProblems(render(pausedCard).marks, clock: clockSpot).isEmpty)

// Ningún texto cortado ni montado en ningún modo.
var cutProblems: [String] = []
var normalTruncated: [String] = []
var textRenders = 0
for mode in DashMode.allCases {
    for theme in [DashTheme.dark, .light] {
        for routeOn in [true, false] {
            for art in [neon, nil] as [CGImage?] {
                let marks = render(musicSnap(.preset(mode), theme, art: art, route: routeOn)).marks
                textRenders += 1
                let tag = "\(mode.label) \(theme.rawValue) \(routeOn ? "con" : "sin") ruta"
                cutProblems += textProblems(marks, clock: clockSpot).map { "\(tag): \($0)" }
                normalTruncated += marks.filter { $0.truncated }.map { "\(tag): «\($0.text)»" }
            }
        }
    }
}
for layout in [largeMusicLayout, sideLayout] {
    for routeOn in [true, false] {
        let marks = render(musicSnap(layout, .dark, art: neon, route: routeOn)).marks
        textRenders += 1
        cutProblems += textProblems(marks, clock: clockSpot).map { "\(layout.template.rawValue): \($0)" }
        normalTruncated += marks.filter { $0.truncated }.map { "\(layout.template.rawValue): «\($0.text)»" }
    }
}
check("Ningún texto cortado, montado ni encima de la hora (todos los modos, día y noche, con y sin ruta)", cutProblems.isEmpty,
      cutProblems.isEmpty ? "\(textRenders) composiciones" : cutProblems.prefix(8).joined(separator: "; "))
check("Con datos normales ningún texto necesita «…»", normalTruncated.isEmpty, normalTruncated.prefix(6).joined(separator: "; "))

// Textos largos: se acortan con «…» sin salirse, y solo el título o el artista.
var longProblems: [String] = []
for mode in [DashMode.music, .split, .musicNotices, .gpsMusic, .full] {
    var s = musicSnap(.preset(mode), .dark, art: neon)
    s.music.title = "Una canción con un título larguísimo para probar el reproductor en la moto"
    s.music.artist = "Artista invitado con un nombre también bastante largo"
    let marks = render(s).marks
    longProblems += textProblems(marks, clock: clockSpot).map { "\(mode.label): \($0)" }
    for m in marks where m.truncated && !(s.music.title.hasSuffix(m.text) || s.music.artist.hasSuffix(m.text)) {
        longProblems.append("\(mode.label): «\(m.text)» acortado")
    }
}
check("Títulos y artistas largos: se acortan con «…» sin salirse de su sitio", longProblems.isEmpty, longProblems.prefix(6).joined(separator: "; "))
var noMusicProblems: [String] = []
for mode in [DashMode.music, .split, .musicNotices, .gpsMusic] {
    var s = musicSnap(.preset(mode), .dark, art: nil)
    s.music = MusicSnapshot()
    let marks = render(s).marks
    if !marks.contains(where: { $0.text == "Sin música" }) { noMusicProblems.append("\(mode.label): falta «Sin música»") }
    noMusicProblems += textProblems(marks, clock: clockSpot).map { "\(mode.label): \($0)" }
}
check("Sin música: el mismo aviso en todas las formas, sin cortes", noMusicProblems.isEmpty, noMusicProblems.joined(separator: "; "))

// Otra resolución (640×320): mismas reglas.
let smallClock = DashLayoutEngine.statusClock(in: CGRect(x: 0, y: 0, width: 640, height: 320), k: 0.8)
var smallProblems: [String] = []
for mode in DashMode.allCases {
    let marks = render(musicSnap(.preset(mode), .dark, art: neon), width: 640, height: 320).marks
    smallProblems += textProblems(marks, width: 640, height: 320, clock: smallClock).map { "\(mode.label): \($0)" }
}
check("A 640×320 tampoco hay textos cortados ni montados", smallProblems.isEmpty, smallProblems.prefix(6).joined(separator: "; "))

// La vista previa del iPhone es el mismo dibujo que recibe la moto.
func imageBytes(_ image: CGImage?) -> [UInt8] {
    guard let image = image else { return [] }
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    data.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}
var previewDiff = 0
for mode in [DashMode.split, .gpsMusic, .music, .musicNotices] {
    let s = musicSnap(.preset(mode), .dark, art: neon)
    previewDiff = max(previewDiff, maxDifference(imageBytes(DashPreview.image(s, now: now)), imageBytes(render(s).px.image)))
}
check("La vista previa del iPhone y la imagen de la moto salen del mismo dibujo (idénticas)", previewDiff == 0, "diferencia máxima \(previewDiff)")

// Maniobra compacta en las zonas con mapa (pantalla dividida y diseños por zonas).
let splitNav = DashLayoutEngine.frames(.preset(.split), in: zoneArea, gap: 6).first { $0.module == .nav }?.rect ?? .null
let navCompact = NavZoneLayout.make(splitNav, OverlaySettings(), k: 1, reserve: nil, trip: true)
check("Dividida: la tarjeta de la maniobra es la misma que en el mapa completo (200×96; antes 426×155)",
      navCompact.card.size == CGSize(width: 200, height: 96), String(format: "%.0f×%.0f", navCompact.card.width, navCompact.card.height))
let oldPad = (splitNav.height * 0.03).rounded() + 2
let oldCard = splitNav.width - 2 * oldPad
let oldCovered = oldCard * splitNav.height * 0.4 + (splitNav.width - 2 * oldPad - 70) * max(11, splitNav.height * 0.062) * 1.9
let newCovered = navCompact.card.width * navCompact.card.height + navCompact.trip.width * navCompact.trip.height
let zoneSize = splitNav.width * splitNav.height
check("Dividida: se ve más mapa (al menos el 80 % de la zona libre de tarjetas)", 1 - newCovered / zoneSize >= 0.8,
      String(format: "mapa libre: %.0f %% (antes %.0f %%)", (1 - newCovered / zoneSize) * 100, (1 - oldCovered / zoneSize) * 100))
var largeNav = OverlaySettings()
largeNav.maneuverSize = .large
let navLarge = NavZoneLayout.make(splitNav, largeNav, k: 1, reserve: nil, trip: true)
check("Dividida: si se elige la tarjeta grande, es más grande pero proporcional a la zona",
      navLarge.card.width > navCompact.card.width && navLarge.card.width <= splitNav.width * 0.7 + 0.5 && navLarge.card.height <= splitNav.height * 0.42 + 0.5,
      String(format: "%.0f×%.0f", navLarge.card.width, navLarge.card.height))
var spotProblems: [String] = []
var spotCount = 0
for spot in CardSpot.allCases {
    for size in CardSize.allCases {
        for mirrored in [false, true] {
            var o = OverlaySettings()
            o.maneuverSpot = spot
            o.maneuverSize = size
            var layout = DashLayout.preset(.split)
            layout.mirrored = mirrored
            layout.overlay = o
            guard let zone = DashLayoutEngine.frames(layout, in: zoneArea, gap: 6).first(where: { $0.module == .nav })?.rect else { continue }
            spotCount += 1
            let L = NavZoneLayout.make(zone, o, k: 1, reserve: zone.intersects(clockSpot) ? clockSpot : nil, trip: true)
            let tag = "\(spot.rawValue) \(size.rawValue)\(mirrored ? " (zona a la derecha)" : "")"
            let parts: [(String, CGRect)] = [("tarjeta", L.card), ("viaje", L.trip), ("brújula", L.compass)]
            for (i, a) in parts.enumerated() {
                if !zone.insetBy(dx: -0.5, dy: -0.5).contains(a.1) { spotProblems.append("\(tag): \(a.0) se sale") }
                if a.1.intersects(clockSpot) { spotProblems.append("\(tag): \(a.0) tapa la hora") }
                for b in parts[(i + 1)...] where a.1.intersects(b.1) { spotProblems.append("\(tag): \(a.0) y \(b.0) se montan") }
            }
            let left = L.card.midX < zone.midX - 1
            let right = L.card.midX > zone.midX + 1
            let upper = L.card.midY < zone.midY
            let inSpot: Bool
            switch spot {
            case .topLeft: inSpot = left && upper
            case .topRight: inSpot = right && upper
            case .bottomLeft: inSpot = left && !upper
            case .bottomRight: inSpot = right && !upper
            case .bottomCenter: inSpot = !left && !right && !upper
            }
            if !inSpot { spotProblems.append("\(tag): la tarjeta no está donde se eligió") }
            // Por delante de la moto (centro de la zona, de la moto hacia arriba) queda libre.
            let ahead = CGRect(x: zone.midX - 16, y: zone.minY + zone.height * 0.25, width: 32, height: zone.height * 0.47)
            if size == .compact && spot.isTop && L.card.intersects(ahead) { spotProblems.append("\(tag): tapa la ruta por delante") }
        }
    }
}
check("Dividida: la maniobra va donde se eligió en el iPhone, sin tapar la hora, el viaje, la brújula ni la ruta por delante",
      spotProblems.isEmpty, spotProblems.isEmpty ? "\(spotCount) combinaciones" : spotProblems.prefix(6).joined(separator: "; "))
var overlayFree: [String] = []
for mode in [DashMode.gps, .gpsMusic, .full, .gpsNotices] {
    let cards = DashLayoutEngine.overlayCards(DashLayout.preset(mode).overlay, in: fullImage, k: 1)
    let covered = cards.filter { $0.item != .compass }.reduce(0) { $0 + $1.rect.width * $1.rect.height }
    overlayFree.append(String(format: "%@ %.0f %%", mode.label, (1 - covered / (W * H)) * 100))
}
let maneuverSizes = [DashMode.gps, .gpsMusic, .full, .gpsNotices].compactMap { mode in
    DashLayoutEngine.overlayCards(DashLayout.preset(mode).overlay, in: fullImage, k: 1).first { $0.item == .maneuver }?.rect.size
}
check("Nav + Música, Completo y Nav + Avisos usan la misma maniobra compacta que Navegación (200×96)",
      maneuverSizes.count == 4 && maneuverSizes.allSatisfy { $0 == CGSize(width: 200, height: 96) }, "mapa libre: " + overlayFree.joined(separator: ", "))

// Cobertura del mapa guardado.
let covComplete = MapCoverageState.make(routeActive: true, remaining: 12_400, continuous: 12_390, horizon: 12_600, cached: 80, capacity: 800)
let covSaving = MapCoverageState.make(routeActive: true, remaining: 12_400, continuous: 3_200, horizon: 12_600, cached: 20, capacity: 800)
let covPartial = MapCoverageState.make(routeActive: true, remaining: 160_000, continuous: 141_000, horizon: 141_600, cached: 800, capacity: 800)
let covNone = MapCoverageState.make(routeActive: false, remaining: 0, continuous: 0, horizon: 0, cached: 0, capacity: 800)
check("Cobertura: ruta completa, guardando y parcial (por memoria) se distinguen",
      covComplete.kind == .complete && covSaving.kind == .saving && covPartial.kind == .partial && covNone.kind == .none && covNone.text.isEmpty,
      "\(covComplete.text) | \(covSaving.text) | \(covPartial.text)")
check("Cobertura: se informan los kilómetros que de verdad tienen mapa seguido",
      covSaving.text == "Guardando el mapa: 3.2 km de 12 km" && covPartial.text == "Mapa parcial: 141 km de 160 km (límite de memoria)"
      && covComplete.text == "Ruta completa guardada: 12 km")
let lowCoverage = MapCoverageState.make(routeActive: true, remaining: 30_000, continuous: 1_400, horizon: 30_200, cached: 30, capacity: 800)
check("Moto: aviso «MAPA GUARDADO» solo con el mapa guardado en uso y menos de 2 km",
      lowCoverage.tftTag(storedMapInUse: true) == "MAPA GUARDADO: 1.4 KM" && lowCoverage.tftTag(storedMapInUse: false) == nil
      && covComplete.tftTag(storedMapInUse: true) == nil && covSaving.tftTag(storedMapInUse: true) == nil,
      lowCoverage.tftTag(storedMapInUse: true) ?? "sin aviso")
let storedBase = MapBase(
    image: testStreets(night: true), data: nil, pixelWidth: 800, pixelHeight: 400, center: center, heading: heading,
    pitch: 0, night: true, live: false, anchor: 160, created: now.timeIntervalSinceReferenceDate, styleKey: "prueba",
    samples: samplePoints.map { ($0, camera($0)) }
)
var lowSnap = musicSnap(.preset(.gpsMusic), .dark, art: neon)
lowSnap.map = storedBase
lowSnap.mapCoverage = lowCoverage
let lowRender = render(lowSnap)
var lowLive = lowSnap
lowLive.map = base
let lowSplit = { () -> [HUDRenderer.TextMark] in
    var s = lowSnap
    s.layout = .preset(.split)
    return render(s).marks
}()
check("Moto: el aviso se dibuja sin tapar nada (mapa completo y pantalla dividida)",
      lowRender.marks.contains { $0.text == "MAPA GUARDADO: 1.4 KM" } && !render(lowLive).marks.contains { $0.text.hasPrefix("MAPA GUARDADO") }
      && textProblems(lowRender.marks, clock: clockSpot).isEmpty && lowSplit.contains { $0.text == "MAPA GUARDADO: 1.4 KM" }
      && textProblems(lowSplit, clock: clockSpot).isEmpty)
if let image = lowRender.px.image { save(image, "064-aviso-mapa-guardado") }

// Precarga: más imágenes a la vez y más memoria.
let wait2 = driveCorridor(corridorRoute, seconds: 40, speed: 0, imageSeconds: 2, parallel: 2, capacity: 400)
let wait3 = driveCorridor(corridorRoute, seconds: 40, speed: 0, imageSeconds: 2, parallel: MapCorridor.parallelPrefetch, capacity: MapCorridor.maxImages)
let wait2Coverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: wait2.entries, northUp: false).continuous
let wait3Coverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: wait3.entries, northUp: false).continuous
check("Precarga antes de salir: con 3 imágenes a la vez se guarda más ruta en el mismo tiempo",
      wait3Coverage >= wait2Coverage * 1.35 && wait3.repeated == 0,
      String(format: "en 40 s (2 s por imagen): %.1f km; antes %.1f km", wait3Coverage / 1000, wait2Coverage / 1000))
let ready3 = driveCorridor(corridorRoute, seconds: 70, speed: 0, imageSeconds: 2, parallel: MapCorridor.parallelPrefetch, capacity: MapCorridor.maxImages)
let ready3State = MapCoverageState.make(routeActive: true, remaining: corridorRoute.length,
                                        continuous: CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: ready3.entries, northUp: false).continuous,
                                        horizon: CorridorPlanner.horizon(remaining: corridorRoute.length, capacity: MapCorridor.maxImages, step: corridorStep),
                                        cached: ready3.entries.count, capacity: MapCorridor.maxImages)
check("Ruta de 15 km: «Ruta completa guardada» en poco más de un minuto con el iPhone desbloqueado", ready3State.kind == .complete,
      "\(ready3State.text) (\(ready3.requests) imágenes)")
let h400 = CorridorPlanner.horizon(remaining: 120_000, capacity: 400, step: corridorStep)
let h800 = CorridorPlanner.horizon(remaining: 120_000, capacity: MapCorridor.maxImages, step: corridorStep)
check("Con 800 imágenes cabe una ruta de 120 km entera (antes, unos 70 km)", h800 >= 120_000 && h400 < 120_000,
      String(format: "%.0f km → %.0f km", h400 / 1000, min(h800, 120_000) / 1000))
check("Memoria del mapa guardado: hasta 96 MB y nunca más de la quinta parte de la libre",
      MapCorridor.budget(available: 2_000 << 20) == 96 << 20 && MapCorridor.budget(available: 300 << 20) == 60 << 20
      && MapCorridor.budget(available: 40 << 20) == 16 << 20)

// Hora actual y llegada en las formas nuevas.
let tripMarks = render(musicSnap(.preset(.split), .dark, art: neon)).marks
let etaClock063 = HUDFormat.clock(now.addingTimeInterval(18 * 60))
check("Dividida: «Llegada», hora de llegada, tiempo y distancia por separado, y la hora actual arriba",
      ["Llegada", etaClock063.time, "18 min", "7.4 km"].allSatisfy { t in tripMarks.contains { $0.text == t } }
      && tripMarks.contains { $0.text == HUDFormat.clock(now).time && clockSpot.contains($0.rect) })

// 10f. Rediseño premium (0.6.3): mismas posiciones que la 0.6.2, las mismas piezas en todas las
// tarjetas (vidrio con borde luminoso), datos del viaje y avisos como en la referencia.
func overlayRect(_ mode: DashMode, _ item: OverlayItem) -> CGRect? {
    DashLayoutEngine.overlayCards(DashLayout.preset(mode).overlay, in: fullImage, k: 1, showNotices: true).first { $0.item == item }?.rect
}
let expectedOverlay: [(DashMode, OverlayItem, CGRect)] = [
    (.gps, .maneuver, CGRect(x: 12, y: 12, width: 200, height: 96)),
    (.gps, .trip, CGRect(x: 200, y: 342, width: 400, height: 46)),
    (.gps, .time, CGRect(x: 672, y: 12, width: 116, height: 30)),
    (.gpsMusic, .maneuver, CGRect(x: 12, y: 12, width: 200, height: 96)),
    (.gpsMusic, .music, CGRect(x: 538, y: 50, width: 250, height: 84)),
    (.gpsMusic, .trip, CGRect(x: 200, y: 342, width: 400, height: 46)),
    (.full, .music, CGRect(x: 538, y: 50, width: 250, height: 84)),
    (.full, .notices, CGRect(x: 526, y: 142, width: 262, height: 58)),
    (.gpsNotices, .notices, CGRect(x: 526, y: 50, width: 262, height: 58)),
]
let expectedZones: [(DashMode, DashModule, CGRect)] = [
    (.split, .nav, CGRect(x: 6, y: 6, width: 454, height: 388)),
    (.split, .music, CGRect(x: 466, y: 6, width: 328, height: 388)),
    (.music, .music, CGRect(x: 6, y: 6, width: 788, height: 388)),
    (.musicNotices, .music, CGRect(x: 6, y: 6, width: 454, height: 388)),
    (.musicNotices, .notices, CGRect(x: 466, y: 6, width: 328, height: 388)),
]
var moved: [String] = []
for (mode, item, rect) in expectedOverlay where overlayRect(mode, item) != rect {
    moved.append("\(mode.label) \(item.rawValue): \(overlayRect(mode, item).map { "\($0)" } ?? "no está")")
}
for (mode, module, rect) in expectedZones {
    let got = DashLayoutEngine.frames(.preset(mode), in: zoneArea, gap: 6).first { $0.module == module }?.rect
    if got != rect { moved.append("\(mode.label) \(module.rawValue): \(got.map { "\($0)" } ?? "no está")") }
}
check("Rediseño: tarjetas y zonas en el mismo sitio y del mismo tamaño que en la 0.6.2 (y la hora fija)", moved.isEmpty,
      moved.isEmpty ? "\(expectedOverlay.count) tarjetas y \(expectedZones.count) zonas" : moved.joined(separator: "; "))

// Las tarjetas comparten el borde luminoso del vidrio (de noche, más claro y azulado que el interior).
let fullNight = render(musicSnap(.preset(.full), .dark, art: neon)).px
let splitNight = render(musicSnap(.preset(.split), .dark, art: neon)).px
var edgeProblems: [String] = []
var edgeCount = 0
let splitNavZone = DashLayoutEngine.frames(.preset(.split), in: zoneArea, gap: 6).first { $0.module == .nav }?.rect ?? .null
let splitNavCards = NavZoneLayout.make(splitNavZone, OverlaySettings(), k: 1, reserve: nil, trip: true)
let edgeCases: [(String, (image: CGImage?, data: [UInt8], rowBytes: Int), CGRect?)] = [
    ("maniobra", fullNight, overlayRect(.full, .maneuver)), ("viaje", fullNight, overlayRect(.full, .trip)),
    ("avisos", fullNight, overlayRect(.full, .notices)), ("hora", fullNight, overlayRect(.full, .time)),
    ("maniobra en Dividida", splitNight, splitNavCards.card), ("viaje en Dividida", splitNight, splitNavCards.trip),
]
for (name, px, rect) in edgeCases {
    guard let r = rect else { edgeProblems.append("\(name): no está"); continue }
    edgeCount += 1
    let x = r.minX + min(24, r.width / 4)
    let edge = rgbAt(px, x, r.minY + 0.5)
    let inside = rgbAt(px, x, r.minY + 6)
    if !(edge.luminance > inside.luminance + 0.02 && edge.b > edge.r + 0.05) {
        edgeProblems.append(String(format: "%@: borde %.2f,%.2f,%.2f / dentro %.2f,%.2f,%.2f", name, edge.r, edge.g, edge.b, inside.r, inside.g, inside.b))
    }
}
check("Rediseño: maniobra, viaje, avisos, hora y zonas usan el mismo vidrio con borde luminoso", edgeProblems.isEmpty,
      edgeProblems.isEmpty ? "\(edgeCount) tarjetas" : edgeProblems.joined(separator: "; "))

// Los fondos de las tarjetas se guardan ya dibujados: se ven igual que dibujados cada vez.
HUDRenderer.cacheCards = false
let directCards = [DashMode.full, .split, .musicNotices, .gpsNotices].map { render(musicSnap(.preset($0), .dark, art: neon)).px.data }
    + [render(musicSnap(.preset(.gpsMusic), .light, art: blue, source: "Apple Music")).px.data]
HUDRenderer.cacheCards = true
let cachedCards = [DashMode.full, .split, .musicNotices, .gpsNotices].map { render(musicSnap(.preset($0), .dark, art: neon)).px.data }
    + [render(musicSnap(.preset(.gpsMusic), .light, art: blue, source: "Apple Music")).px.data]
let cardCacheDiff = zip(directCards, cachedCards).map { maxDifference($0.0, $0.1) }.max() ?? 255
var cacheWhere = ""
for (n, pair) in zip(directCards, cachedCards).enumerated() {
    var worst = 0
    var at = 0
    for i in 0..<min(pair.0.count, pair.1.count) where abs(Int(pair.0[i]) - Int(pair.1[i])) > worst {
        worst = abs(Int(pair.0[i]) - Int(pair.1[i]))
        at = i
    }
    if worst == cardCacheDiff { cacheWhere = "caso \(n), x \((at / 4) % Int(W)), y \((at / 4) / Int(W)), canal \(at % 4): \(pair.0[at]) / \(pair.1[at])" }
}
check("Rediseño: las tarjetas guardadas ya dibujadas se ven igual que dibujadas cada vez", cardCacheDiff <= 4,
      "diferencia máxima \(cardCacheDiff) de 255 (\(cacheWhere))")

// Datos del viaje como en la referencia: Distancia | Restante | Llegada, cada cifra sobre su nombre.
let navMarks = render(musicSnap(.preset(.gps), .dark, art: neon)).marks
func markRect(_ t: String, in marks: [HUDRenderer.TextMark]) -> CGRect? { marks.first { $0.text == t }?.rect }
let tripOrder = ["Distancia", "Restante", "Llegada"].compactMap { markRect($0, in: navMarks)?.midX }
let valueOverLabel = [("7.4 km", "Distancia"), ("18 min", "Restante")].allSatisfy { v, l in
    guard let a = markRect(v, in: navMarks), let b = markRect(l, in: navMarks) else { return false }
    return a.maxY <= b.minY + 1 && abs(a.midX - b.midX) < 2
}
check("Rediseño: datos del viaje en tres bloques (Distancia, Restante, Llegada), cada cifra sobre su nombre",
      tripOrder.count == 3 && tripOrder[0] < tripOrder[1] && tripOrder[1] < tripOrder[2] && valueOverLabel,
      tripOrder.map { String(format: "%.0f", $0) }.joined(separator: " < "))
let clockTexts = navMarks.filter { clockSpot.contains($0.rect) }.map { $0.text }
let etaText = HUDFormat.clock(now.addingTimeInterval(18 * 60)).time
check("Rediseño: la hora actual (con su reloj, arriba) y la de llegada (con «Llegada», abajo) no se confunden",
      clockTexts.contains(HUDFormat.clock(now).time) && !clockTexts.contains("Llegada") && !clockTexts.contains(etaText)
      && navMarks.contains { $0.text == etaText && !clockSpot.intersects($0.rect) }
      && navMarks.contains { $0.text == "Llegada" && $0.rect.minY > H / 2 },
      "arriba: \(clockTexts.joined(separator: " ")); llegada: \(etaText)")

// Avisos: remitente, título, mensaje y hora; sin avisos, un estado vacío centrado.
let mnMarks = render(musicSnap(.preset(.musicNotices), .dark, art: neon, route: false)).marks
let noticeTexts = ["NAVEGACIÓN", "Ruta iniciada", "18 min hasta el destino", "Ahora", "IPHONE", "Batería del iPhone", "2 min"]
check("Rediseño: cada aviso con su remitente, título, mensaje y hora", noticeTexts.allSatisfy { t in mnMarks.contains { $0.text == t } },
      noticeTexts.filter { t in !mnMarks.contains { $0.text == t } }.joined(separator: ", "))
var emptyNotices = musicSnap(.preset(.musicNotices), .dark, art: neon, route: false)
emptyNotices.notices = []
let emptyMarks = render(emptyNotices).marks
let noticesZone = DashLayoutEngine.frames(.preset(.musicNotices), in: zoneArea, gap: 6).first { $0.module == .notices }?.rect ?? .null
check("Rediseño: sin avisos se ve un estado vacío centrado, no la zona en blanco",
      markRect("Sin avisos", in: emptyMarks).map { abs($0.midX - noticesZone.midX) < 2 && $0.midY > noticesZone.minY + 120 } == true
      && emptyMarks.contains { $0.text.hasPrefix("Aquí aparecen") } && textProblems(emptyMarks, clock: clockSpot).isEmpty)

// Mapa: la ruta lleva resplandor y la posición la marca azul de la referencia.
if let q = base?.project(center.moved(250, bearing: heading + 180).moved(380, bearing: heading)) {
    let x = q.x * W
    let y = q.y * H
    let sides = [rgbAt(check1, x - 14, y), rgbAt(check1, x + 14, y)]
    check("Rediseño: la ruta lleva un resplandor azul a los lados (más contraste sobre el mapa)", sides.allSatisfy { $0.b > $0.r + 0.12 },
          sides.map { String(format: "%.2f,%.2f,%.2f", $0.r, $0.g, $0.b) }.joined(separator: " | "))
}
if let q = base?.project(center.moved(90, bearing: heading + 180)) {
    // La moto va a 160 m del inicio de la ruta de prueba; se busca alrededor por si acaso.
    var arrow = 0
    var disk = 0
    for dy in -30...30 {
        for dx in -30...30 {
            let c = rgbAt(check1, min(W - 1, max(0, q.x * W + CGFloat(dx))), min(H - 1, max(0, q.y * H + CGFloat(dy))))
            if c.b > 0.75 && c.r < 0.45 { arrow += 1 }
            if c.b > 0.15 && c.b < 0.3 && c.r < 0.1 { disk += 1 }
        }
    }
    check("Rediseño: la posición se marca con la flecha azul en su disco de vidrio", arrow > 120 && disk > 300,
          "flecha \(arrow) px, disco \(disk) px")
}

// Rendimiento de todos los modos con el rediseño.
var perfAll: [String] = []
var perfMax = 0.0
let perfAllRenderer = HUDRenderer(width: Int(W), height: Int(H))
for mode in DashMode.allCases {
    let snap = musicSnap(.preset(mode), .dark, art: neon)
    _ = DashPreview.image(snap, now: now, renderer: perfAllRenderer)
    let t0 = Date()
    for _ in 0..<30 { _ = DashPreview.image(snap, now: now, renderer: perfAllRenderer) }
    let ms = Date().timeIntervalSince(t0) * 1000 / 30
    perfMax = max(perfMax, ms)
    perfAll.append(String(format: "%@ %.1f", mode.label, ms))
}
check("Rediseño: ningún modo tarda más de 25 ms por fotograma (la moto recibe 10 por segundo)", perfMax < 25, perfAll.joined(separator: ", ") + " ms")

// 10g. Versión 0.6.4: botones del reproductor (solo dibujo) y acabado premium.
let musicPlaces: [(name: String, layout: DashLayout, route: Bool, minButton: CGFloat)] = [
    ("Música completa", .preset(.music), false, 56),
    ("Música completa con ruta", .preset(.music), true, 56),
    ("Dividida", .preset(.split), true, 40),
    ("Música + Avisos", .preset(.musicNotices), false, 40),
    ("Música + Avisos con ruta", .preset(.musicNotices), true, 24),
    ("Nav + Música", .preset(.gpsMusic), true, 20),
    ("Completo", .preset(.full), true, 20),
    ("Personalizado", .preset(.custom), true, 20),
    ("Tarjeta grande", largeMusicLayout, true, 24),
    ("Principal + 2", sideLayout, true, 24),
]
var buttonProblems: [String] = []
var buttonSizes: [String] = []
var stateProblems: [String] = []
var iconContrast = 99.0
var iconContrastWhere = ""
for place in musicPlaces {
    for theme in [DashTheme.dark, .light] {
        for playing in [true, false] {
            var s = musicSnap(place.layout, theme, art: theme == .dark ? neon : blue, source: theme == .dark ? "Spotify" : "Apple Music", route: place.route)
            s.music.playing = playing
            let shown = render(s)
            let tag = "\(place.name) \(theme == .dark ? "noche" : "día")\(playing ? "" : " en pausa")"
            let kinds = shown.controls.map { $0.kind }
            let expected = ["anterior", playing ? "pausa" : "reproducir", "siguiente"]
            guard kinds == expected else {
                buttonProblems.append("\(tag): \(kinds.joined(separator: ", ")) en vez de \(expected.joined(separator: ", "))")
                continue
            }
            let prev = shown.controls[0].rect
            let play = shown.controls[1].rect
            let next = shown.controls[2].rect
            for c in shown.controls {
                if !c.box.insetBy(dx: -0.5, dy: -0.5).contains(c.rect) { buttonProblems.append("\(tag): «\(c.kind)» se sale de su zona o tarjeta") }
                if c.alpha < 0.99 { buttonProblems.append("\(tag): «\(c.kind)» apagado con música") }
                if c.rect.intersects(clockSpot) { buttonProblems.append("\(tag): «\(c.kind)» tapa la hora") }
                for t in shown.marks where !t.text.trimmingCharacters(in: .whitespaces).isEmpty
                    && t.rect.insetBy(dx: 0.5, dy: 0.5).intersects(c.rect.insetBy(dx: -1, dy: -1)) {
                    buttonProblems.append("\(tag): «\(c.kind)» toca el texto «\(t.text)»")
                }
            }
            // Proporciones: círculo de reproducir/pausar grande y laterales menores, a la misma
            // distancia a cada lado.
            let ratio = prev.height / play.height
            let left = play.midX - prev.midX
            let right = next.midX - play.midX
            if play.width < place.minButton { buttonProblems.append(String(format: "%@: círculo de %.0f px (mínimo %.0f)", tag, play.width, place.minButton)) }
            if ratio < 0.3 || ratio > 0.6 { buttonProblems.append(String(format: "%@: laterales al %.0f %% del círculo", tag, ratio * 100)) }
            if abs(left - right) > 1.01 || abs(prev.midY - play.midY) > 1.01 || abs(next.midY - play.midY) > 1.01 {
                buttonProblems.append("\(tag): botones desalineados")
            }
            if theme == .dark && playing { buttonSizes.append(String(format: "%@ %.0f", place.name, play.width)) }
            // El símbolo del círculo según el estado: con ❚❚ el centro del círculo queda libre
            // (entre las dos barras); con ▶ el centro es el triángulo.
            let bare = render(s, hideText: true).px
            let colors = MusicCardColors.make(style: .dynamic, palette: s.music.palette, night: s.night, intensity: s.musicIntensity,
                                              spotify: s.music.source == "Spotify")
            let center = rgbAt(bare, play.midX, play.midY)
            let ring = rgbAt(bare, play.midX, play.minY + play.height * 0.14)
            let bar = rgbAt(bare, play.midX - play.width * 0.1175, play.midY)
            let disc = colors.text
            if colorDistance(ring, disc) > 0.12 { stateProblems.append("\(tag): el círculo no es del color del texto") }
            if playing {
                if colorDistance(center, disc) > 0.12 || colorDistance(bar, disc) < 0.4 { stateProblems.append("\(tag): no se ven las dos barras de pausa") }
            } else if colorDistance(center, disc) < 0.4 {
                stateProblems.append("\(tag): no se ve el triángulo de reproducir")
            }
            // Contraste de los iconos con el fondo que tienen detrás (mínimo 3:1, como pide la
            // norma de accesibilidad para iconos).
            let behind = render(s, hideText: true, hideControls: true).px
            for c in shown.controls {
                let q = c.kind == "anterior" || c.kind == "siguiente" ? c.rect.insetBy(dx: -2, dy: -2) : c.rect.insetBy(dx: -3, dy: -3)
                for pt in [CGPoint(x: q.minX, y: q.minY), CGPoint(x: q.maxX, y: q.minY), CGPoint(x: q.minX, y: q.maxY),
                           CGPoint(x: q.maxX, y: q.maxY), CGPoint(x: q.midX, y: q.midY)] {
                    let value = disc.contrast(with: rgbAt(behind, pt.x, pt.y))
                    if value < iconContrast {
                        iconContrast = value
                        iconContrastWhere = "\(tag) «\(c.kind)»"
                    }
                }
            }
        }
    }
}
check("0.6.4: anterior, reproducir/pausar y siguiente en todos los modos con música, dentro de su sitio y sin tocar textos ni la hora",
      buttonProblems.isEmpty, buttonProblems.isEmpty ? "\(musicPlaces.count) sitios, día y noche, sonando y en pausa" : buttonProblems.prefix(8).joined(separator: "; "))
check("0.6.4: botón central grande (proporcional a cada sitio) y laterales menores, alineados", buttonProblems.isEmpty,
      "círculo en px: " + buttonSizes.joined(separator: ", "))
check("0.6.4: el botón central muestra el estado real (❚❚ sonando, ▶ en pausa)", stateProblems.isEmpty, stateProblems.prefix(6).joined(separator: "; "))
check("0.6.4: iconos con contraste suficiente sobre su fondo (≥ 3:1, día y noche)", iconContrast >= 3,
      String(format: "peor %.1f:1 (%@)", iconContrast, iconContrastWhere))

// Sin música: los botones se ven, apagados, con ▶.
var idleButtons: [String] = []
for mode in [DashMode.music, .split, .musicNotices, .gpsMusic, .full] {
    var s = musicSnap(.preset(mode), .dark, art: nil)
    s.music = MusicSnapshot()
    let c = render(s).controls
    if c.count != 3 || c.contains(where: { $0.alpha > 0.5 }) || !c.contains(where: { $0.kind == "reproducir" }) {
        idleButtons.append(mode.label)
    }
}
check("0.6.4: sin música los botones se ven apagados (con ▶)", idleButtons.isEmpty, idleButtons.joined(separator: ", "))

// Cambio entre reproducir y pausa: fundido corto (a mitad, el centro del círculo está entre
// los dos estados).
var ppSnap = musicSnap(.preset(.split), .dark, art: neon)
let ppPlay = render(ppSnap, hideText: true)
let ppCircle = ppPlay.controls.count > 1 ? ppPlay.controls[1].rect : CGRect(x: 0, y: 0, width: 2, height: 2)
ppSnap.music.playing = false
let ppPause = render(ppSnap, hideText: true)
ppSnap.music.playing = true
ppSnap.playFade = 0.5
let ppMid = render(ppSnap, hideText: true)
let ppLumA = rgbAt(ppPlay.px, ppCircle.midX, ppCircle.midY).luminance
let ppLumB = rgbAt(ppPause.px, ppCircle.midX, ppCircle.midY).luminance
let ppLumM = rgbAt(ppMid.px, ppCircle.midX, ppCircle.midY).luminance
check("0.6.4: el cambio ▶/❚❚ se funde (sin saltos)", ppLumM > min(ppLumA, ppLumB) + 0.05 && ppLumM < max(ppLumA, ppLumB) - 0.05,
      String(format: "centro del círculo: sonando %.2f, a mitad %.2f, en pausa %.2f", ppLumA, ppLumM, ppLumB))

// La tarjeta de música no crece: mide lo mismo que en la 0.6.3.
let compactCardRect = musicCard(DashLayout.preset(.gpsMusic).overlay) ?? .zero
let largeCardRect = musicCard(largeMusic) ?? .zero
check("0.6.4: las tarjetas de música miden lo mismo que en la 0.6.3 (250×84 y 300×124)",
      compactCardRect.size == CGSize(width: 250, height: 84) && largeCardRect.size == CGSize(width: 300, height: 124),
      "\(compactCardRect.size) y \(largeCardRect.size)")

// Portadas que no son cuadradas: se ven enteras, sin estirarse.
func wideArt() -> CGImage? {
    let w = 200
    let h = 100
    guard let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    g.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
    g.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return g.makeImage()
}
var wideSnap = musicSnap(.preset(.split), .dark, art: wideArt())
wideSnap.musicStyle = .dark
let wideRender = render(wideSnap, hideText: true)
let wideArtRect = playerLayout(musicZone(.preset(.split)) ?? .zero, nil).artwork
let wideMid = rgbAt(wideRender.px, wideArtRect.midX, wideArtRect.midY)
let wideTop = rgbAt(wideRender.px, wideArtRect.midX, wideArtRect.minY + wideArtRect.height * 0.12)
check("0.6.4: una portada que no es cuadrada se ve entera, sin estirarse", wideMid.r > 0.7 && wideMid.g < 0.3 && wideTop.r < 0.5,
      String(format: "centro %.2f,%.2f,%.2f; franja de arriba %.2f,%.2f,%.2f", wideMid.r, wideMid.g, wideMid.b, wideTop.r, wideTop.g, wideTop.b))

// Capturas de la 0.6.4.
let captures: [(String, DashSnapshot)] = [
    ("064-musica-avisos-con-ruta", musicSnap(.preset(.musicNotices), .dark, art: redBlack)),
    ("064-tarjeta-grande", musicSnap(largeMusicLayout, .dark, art: neon)),
    ("064-tarjeta-grande-dia", musicSnap(largeMusicLayout, .light, art: blue, source: "Apple Music")),
    ("064-principal-mas-2", musicSnap(sideLayout, .dark, art: neon)),
    ("064-completo-roja", musicSnap(.preset(.full), .dark, art: redBlack)),
    ("064-musica-completa-con-ruta", musicSnap(.preset(.music), .dark, art: neon)),
    ("064-musica-completa-roja", musicSnap(.preset(.music), .dark, art: redBlack, route: false)),
]
// Todos los modos, de noche y de día, con datos como los de un viaje real y con los de demostración.
let modeCaptureNames: [(DashMode, String)] = [
    (.gps, "navegacion"), (.gpsMusic, "nav-musica"), (.split, "dividida"), (.music, "musica-completa"), (.full, "completo"),
    (.gpsNotices, "nav-avisos"), (.musicNotices, "musica-avisos"), (.custom, "personalizado"),
]
for (mode, name) in modeCaptureNames {
    if let image = render(musicSnap(.preset(mode), .dark, art: neon, route: mode != .music && mode != .musicNotices)).px.image { save(image, "064-\(name)-noche") }
    if let image = render(musicSnap(.preset(mode), .light, art: blue, source: "Apple Music", route: mode != .music && mode != .musicNotices)).px.image { save(image, "064-\(name)-dia") }
    if let image = render(DashDemo.snapshot(layout: .preset(mode), theme: .dark, now: now)).px.image { save(image, "064-demo-\(name)") }
}
for (name, snap) in captures {
    if let image = render(snap).px.image { save(image, name) }
}
var splitLarge = musicSnap(.preset(.split), .dark, art: neon)
splitLarge.layout.overlay.maneuverSize = .large
if let image = render(splitLarge).px.image { save(image, "064-dividida-maniobra-grande") }
var splitRight = musicSnap(.preset(.split), .dark, art: neon)
splitRight.layout.mirrored = true
splitRight.layout.overlay.maneuverSpot = .topRight
if let image = render(splitRight).px.image { save(image, "064-dividida-a-la-derecha") }
var splitBottom = musicSnap(.preset(.split), .light, art: blue, source: "Apple Music")
splitBottom.layout.overlay.maneuverSpot = .bottomLeft
if let image = render(splitBottom).px.image { save(image, "064-dividida-maniobra-abajo") }
if let image = render(musicSnap(.preset(.split), .dark, art: neon, route: false)).px.image { save(image, "064-dividida-sin-ruta") }
if let image = render(pausedColumn).px.image { save(image, "064-dividida-en-pausa") }
var noMusicSplit = musicSnap(.preset(.split), .dark, art: nil)
noMusicSplit.music = MusicSnapshot()
if let image = render(noMusicSplit).px.image { save(image, "064-dividida-sin-musica") }
var crossCard = musicSnap(.preset(.gpsMusic), .dark, art: neon)
var previousSong = crossCard.music
previousSong.title = "Canción anterior"
previousSong.artist = "Otro artista"
previousSong.artwork = redBlack
crossCard.musicFrom = previousSong
crossCard.musicFade = 0.7
crossCard.paletteFrom = redBlack.flatMap { ArtPalette.extract($0) }
crossCard.paletteFade = 0.7
if let image = render(crossCard).px.image { save(image, "064-tarjeta-transicion") }
var longSplit = musicSnap(.preset(.split), .dark, art: neon)
longSplit.music.title = "Una canción con un título larguísimo para probar el reproductor en la moto"
if let image = render(longSplit).px.image { save(image, "064-titulo-largo") }
if let image = render(musicSnap(.preset(.split), .dark, art: neon), width: 640, height: 320).px.image { save(image, "064-dividida-640x320") }

// 0.6.4: más capturas de los botones (en pausa en la tarjeta, sin música en la tarjeta, a mitad
// del cambio ▶/❚❚ y la portada que no es cuadrada).
if let image = render(pausedCard).px.image { save(image, "064-tarjeta-en-pausa") }
var noMusicCard = musicSnap(.preset(.gpsMusic), .dark, art: nil)
noMusicCard.music = MusicSnapshot()
if let image = render(noMusicCard).px.image { save(image, "064-tarjeta-sin-musica") }
var pausedStage = musicSnap(.preset(.music), .light, art: blue, source: "Apple Music", route: false)
pausedStage.music.playing = false
if let image = render(pausedStage).px.image { save(image, "064-musica-completa-en-pausa-dia") }
if let image = render(wideSnap).px.image { save(image, "064-portada-no-cuadrada") }

// Rendimiento de las formas nuevas.
let perfRenderer = HUDRenderer(width: Int(W), height: Int(H))
var perfCases: [String] = []
var perfWorst = 0.0
for (name, snap) in [("Dividida", musicSnap(.preset(.split), .dark, art: neon)), ("Nav + Música en transición", crossCard),
                     ("Música + Avisos", musicSnap(.preset(.musicNotices), .dark, art: neon))] {
    let t0 = Date()
    for _ in 0..<40 { _ = DashPreview.image(snap, now: now, renderer: perfRenderer) }
    let ms = Date().timeIntervalSince(t0) * 1000 / 40
    perfWorst = max(perfWorst, ms)
    perfCases.append(String(format: "%@ %.1f ms", name, ms))
}
check("Las formas nuevas del reproductor se dibujan en menos de 25 ms por fotograma", perfWorst < 25, perfCases.joined(separator: ", "))

// 11. Rendimiento del dibujo (mapa de calles + tarjetas).
let renderer = HUDRenderer(width: Int(W), height: Int(H))
var snap = streetsSnapshot(.preset(.full), theme: .dark)
snap.music.palette = redBlack.flatMap { ArtPalette.extract($0) }
snap.paletteFrom = blue.flatMap { ArtPalette.extract($0) }
snap.paletteFade = 0.5
let start = Date()
for _ in 0..<100 { _ = DashPreview.image(snap, now: now, renderer: renderer) }
let ms = Date().timeIntervalSince(start) * 10
check("Dibujar un fotograma con mapa y tarjetas tarda menos de 25 ms", ms < 25, String(format: "%.1f ms de media en esta máquina", ms))

let summary = failures == 0 ? "RESULTADO: \(report.count) pruebas, todas pasan" : "RESULTADO: \(failures) de \(report.count) pruebas fallan"
print(summary)
report.append(summary)
try? report.joined(separator: "\n").write(toFile: outDir + "/pruebas-panel.txt", atomically: true, encoding: .utf8)
exit(failures == 0 ? 0 : 1)
