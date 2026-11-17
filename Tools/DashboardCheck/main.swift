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
    check("Amanecer en Guatemala hacia las 6:05", riseMin > 5 * 60 + 45 && riseMin < 6 * 60 + 25, "\(rise.hour ?? 0):\(rise.minute ?? 0)")
    check("Atardecer en Guatemala hacia las 17:30", setMin > 17 * 60 + 5 && setMin < 17 * 60 + 45, "\(set.hour ?? 0):\(set.minute ?? 0)")
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
let corridorRoute = RouteLine(points: legs(corridorStart, [(6000, 35), (4000, 125), (5000, 35)]))
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
func fakeShot(_ here: GeoPoint, heading h: Double, style: String, anchor: Double) -> CorridorEntry? {
    let v = corridorVisible
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
func fillCorridor(_ route: RouteLine, from progress: Double, existing: [CorridorEntry], nightAfter: Double = .infinity, capacity: Int = 400) -> [CorridorEntry] {
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
let small = fillCorridor(corridorRoute, from: 0, existing: [], capacity: 20)
check("Con memoria para 20 imágenes se guarda el tramo más cercano",
      small.count <= 24 && small.allSatisfy { $0.anchor < 20 * corridorStep + 100 }, "\(small.count) imágenes")
let trimmed = CorridorPlanner.trim(fullCorridor, progress: 5000, capacity: 30)
check("Al pasar de largo y con poca memoria se sueltan las de atrás y las más lejanas",
      trimmed.count == 30 && trimmed.allSatisfy { $0.anchor >= 4600 && $0.anchor < 5000 + 31 * corridorStep })

// Huecos: sin imágenes entre 4 y 5 km la cobertura seguida se corta ahí.
let holed = fullCorridor.filter { $0.anchor < 3900 || $0.anchor > 5100 }
let holedCoverage = CorridorCoverage.scan(route: corridorRoute, from: 0, to: corridorRoute.length, entries: holed, northUp: false)
check("Se detecta el tramo sin imagen", holedCoverage.gaps == 1 && holedCoverage.continuous > 3800 && holedCoverage.continuous < 4400,
      String(format: "seguido %.1f km, %d huecos", holedCoverage.continuous / 1000, holedCoverage.gaps))

// Recálculo: la ruta nueva comparte los primeros 6 km y luego va por otro lado.
let rerouted = RouteLine(points: legs(corridorStart, [(6000, 35), (5000, 300)]))
let kept = CorridorPlanner.retain(fullCorridor, on: rerouted, northUp: false)
let keptFirstLeg = kept.filter { $0.anchor < 5900 }.count
let firstLeg = fullCorridor.filter { $0.anchor < 5900 }.count
check("Al recalcular se conservan las imágenes que siguen sobre la ruta nueva (antes se borraban todas)",
      keptFirstLeg >= firstLeg - 1 && kept.allSatisfy { $0.anchor < 6200 }, "\(kept.count) de \(fullCorridor.count)")
let refilled = fillCorridor(rerouted, from: 2000, existing: kept)
let refilledCoverage = CorridorCoverage.scan(route: rerouted, from: 2000, to: rerouted.length, entries: refilled, northUp: false)
check("Tras recalcular, solo se pide el tramo nuevo", refilled.count - kept.count < 45 && refilledCoverage.gaps == 0,
      "\(refilled.count - kept.count) nuevas")

// Qué imagen usa cada fotograma.
func poseAt(_ route: RouteLine, _ d: Double) -> MapPose {
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
let empty = MapChooser.choose(live: nil, entries: [], pose: poseAt(corridorRoute, 3000), wantedStyle: "dia",
                              now: 100, preview: false, northUp: false)
check("Sin imagen que sirva: mapa simple, sin inventar calles", empty.base == nil && empty.source == .none)
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
