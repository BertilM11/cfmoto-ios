// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pruebas del panel (sin moto y sin iPhone) y láminas de cada modo. Se compila en macOS junto
// con el modelo y el dibujo de la app:
//   swiftc Tools/DashboardCheck/main.swift App/HUD/HUDModel.swift App/HUD/HUDRenderer.swift \
//          App/Dashboard/DashModel.swift App/Dashboard/DashRenderer.swift -o dashcheck
//   ./dashcheck carpeta_de_salida
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
components.day = 16
components.hour = 19
components.minute = 4
let now = Calendar.current.date(from: components) ?? Date()

let W: CGFloat = 800
let H: CGFloat = 400
let area = DashLayoutEngine.usableArea(width: W, height: H, reservedBottom: 0.22).insetBy(dx: 5, dy: 5)

// 1. Distribución: dentro del área, sin solapes, sin módulos repetidos.
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

for mode in DashMode.allCases {
    let problem = layoutProblems(DashLayout.preset(mode))
    check("Distribución del modo «\(mode.title)»", problem == nil, problem ?? "")
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
check("2000 diseños personalizados al azar (incluye valores inválidos)", randomProblem == nil, randomProblem ?? "")

// 2. Contenido de cada modo.
func modules(_ mode: DashMode) -> [DashModule] { DashLayout.preset(mode).normalized.slots.compactMap { $0 } }
check("Solo GPS muestra solo navegación", modules(.gps) == [.nav])
check("Solo música muestra solo música", modules(.music) == [.music])
check("GPS + Música", modules(.gpsMusic) == [.nav, .music])
check("GPS + Avisos", modules(.gpsNotices) == [.nav, .notices])
check("Música + Avisos", modules(.musicNotices) == [.music, .notices])
check("Panel completo: navegación, música y avisos", modules(.full) == [.nav, .music, .notices])
check("En los modos con GPS la navegación ocupa la mayor parte", DashLayout.preset(.gpsMusic).split > 0.5 && DashLayout.preset(.full).split > 0.5)

// 3. Edición: mover e intercambiar módulos.
var edit = DashLayout.preset(.full)
edit.swapSlots(0, 2)
check("Intercambiar dos zonas", edit.slots == [.notices, .music, .nav])
edit.place(.music, at: 0)
check("Colocar un módulo que ya estaba en otra zona los intercambia", edit.slots == [.music, .notices, .nav])
edit.place(nil, at: 1)
check("Ocultar un módulo deja la zona vacía", edit.slots == [.music, nil, .nav] && layoutProblems(edit) == nil)
edit.template = .columns
check("Cambiar de plantilla recorta las zonas sobrantes", edit.normalized.slots.count == 2)

// 4. Persistencia.
var config = DashConfig()
config.mode = .custom
config.custom = DashLayout(template: .columns, slots: [.map, .trip], split: 0.5)
config.theme = .light
config.rules.turnPriority = false
config.noticeSeconds = 15
config.profiles.append(DashProfile(name: "Prueba", layout: .preset(.music)))
if let data = config.encoded(), let back = DashConfig.decoded(data) {
    check("La configuración se guarda y se recupera igual", back == config)
} else {
    check("La configuración se guarda y se recupera igual", false, "no se pudo codificar")
}
check("Datos guardados dañados no rompen la carga", DashConfig.decoded(Data("basura".utf8)) == nil)
check("Hay seis perfiles de fábrica", DashConfig().profiles.count == 6)

// 5. Reglas automáticas.
var c = DashConfig()
var auto = DashAutoState()
c.mode = .music
DashRulesEngine.apply(.navStarted, config: &c, auto: &auto)
check("Iniciar ruta en Solo música pasa a GPS + Música", c.mode == .gpsMusic && auto.saved == .music)
DashRulesEngine.apply(.navEnded, config: &c, auto: &auto)
check("Terminar la ruta vuelve al modo anterior", c.mode == .music && auto.saved == nil)
c.mode = .full
DashRulesEngine.apply(.navStarted, config: &c, auto: &auto)
check("Iniciar ruta no cambia un modo que ya muestra el GPS", c.mode == .full)
c.mode = .gps
c.rules.musicOnlyWithoutRoute = true
DashRulesEngine.apply(.musicStarted(routeActive: true), config: &c, auto: &auto)
check("Música con ruta activa no quita el GPS", c.mode == .gps)
DashRulesEngine.apply(.musicStarted(routeActive: false), config: &c, auto: &auto)
check("Música sin ruta pasa a Solo música", c.mode == .music)
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

// 6. Composición: cada modo dibuja algo y la franja de la moto queda intacta.
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

HUDRenderer.reservedBottom = 0.22
let reservedTop = Int(DashLayoutEngine.usableArea(width: W, height: H, reservedBottom: 0.22).height)
for mode in DashMode.allCases {
    for theme in [DashTheme.dark, DashTheme.light] {
        var layout = DashLayout.preset(mode)
        if mode == .custom { layout = DashLayout(template: .mainSide, slots: [.map, .turn, .trip], split: 0.5, sideSplit: 0.55, mirrored: true) }
        let r = pixels(DashDemo.snapshot(layout: layout, theme: theme, now: now))
        var colors = Set<UInt32>()
        var bandClean = true
        let first = (UInt32(r.data[2]) << 16) | (UInt32(r.data[1]) << 8) | UInt32(r.data[0])
        for y in stride(from: 0, to: Int(H), by: 3) {
            for x in stride(from: 0, to: Int(W), by: 3) {
                let o = y * r.rowBytes + x * 4
                let v = (UInt32(r.data[o + 2]) << 16) | (UInt32(r.data[o + 1]) << 8) | UInt32(r.data[o])
                if y >= reservedTop {
                    if v != first { bandClean = false }
                } else {
                    colors.insert(v)
                }
            }
        }
        let name = "«\(mode.title)» \(theme == .dark ? "oscuro" : "claro")"
        check("Composición \(name)", r.image != nil && colors.count > 20, "\(colors.count) colores")
        check("Franja de la moto intacta en \(name)", bandClean)
        if let image = r.image { save(image, "panel-\(mode.rawValue)-\(theme.rawValue)") }
    }
}

// 7. Estados sin datos.
var empty = DashSnapshot()
empty.layout = .preset(.full)
let e = pixels(empty)
check("Panel completo sin ruta, sin música y sin avisos", e.image != nil)
if let image = e.image { save(image, "panel-sin-datos") }
var none = DashSnapshot()
none.layout = DashLayout(template: .columns, slots: [nil, nil])
check("Panel sin módulos no falla", pixels(none).image != nil)
var arrived = DashDemo.snapshot(layout: .preset(.gpsMusic), theme: .dark, now: now)
arrived.nav.navigating = false
arrived.nav.arrived = true
arrived.nav.destinationName = "Destino de demostración"
if let image = pixels(arrived).image { save(image, "panel-llegada") }
var small = DashDemo.snapshot(layout: .preset(.full), theme: .dark, now: now)
small.privacy = true
check("Otra resolución (640x320)", DashPreview.image(small, width: 640, height: 320, now: now) != nil)
check("Sin franja reservada (toda la altura)", { HUDRenderer.reservedBottom = 0; let ok = DashPreview.image(small, now: now) != nil; HUDRenderer.reservedBottom = 0.22; return ok }())

// 8. Rendimiento del dibujo.
let renderer = HUDRenderer(width: Int(W), height: Int(H))
let snap = DashDemo.snapshot(layout: .preset(.full), theme: .dark, now: now)
let start = Date()
for _ in 0..<100 { _ = DashPreview.image(snap, now: now, renderer: renderer) }
let ms = Date().timeIntervalSince(start) * 10
check("Dibujar un fotograma del panel completo tarda menos de 20 ms", ms < 20, String(format: "%.1f ms de media en esta máquina", ms))

let summary = failures == 0 ? "RESULTADO: \(report.count) pruebas, todas pasan" : "RESULTADO: \(failures) de \(report.count) pruebas fallan"
print(summary)
report.append(summary)
try? report.joined(separator: "\n").write(toFile: outDir + "/pruebas-panel.txt", atomically: true, encoding: .utf8)
exit(failures == 0 ? 0 : 1)
