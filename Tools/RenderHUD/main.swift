// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Herramienta de la compilación automática: dibuja la pantalla de la moto en varios casos y
// guarda las imágenes como PNG, para poder revisarlas sin tener la moto delante.
// Uso: renderhud <carpeta de salida>
import Foundation
import CoreGraphics
import ImageIO

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func save(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("no se pudo crear \(url.path)")
        return
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("ok \(url.lastPathComponent)")
}

func canvas(_ width: Int, _ height: Int) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func render(_ snapshot: HUDSnapshot, _ name: String, width: Int = 800, height: Int = 400) {
    let ctx = canvas(width, height)
    HUDRenderer(width: width, height: height).draw(snapshot, now: now, in: ctx)
    if let image = ctx.makeImage() {
        save(image, name)
    }
}

// Una ruta de ejemplo: recto al norte, giro a la derecha, curva suave y giro a la izquierda.
func sampleShape() -> HUDRouteShape {
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

var components = DateComponents()
components.year = 2026
components.month = 11
components.day = 16
components.hour = 17
components.minute = 42
let now = Calendar.current.date(from: components) ?? Date()
let shape = sampleShape()

func guidance(
    _ kind: ManeuverKind, _ distance: Double, _ text: String,
    progress: Double, style: HUDStyle, then: ManeuverKind? = nil
) -> HUDSnapshot {
    var s = HUDSnapshot()
    s.navigating = true
    s.gpsOk = true
    s.kind = kind
    s.distanceToManeuver = distance
    s.instruction = text
    s.thenKind = then
    s.remainingDistance = 7400
    s.remainingTime = 18 * 60
    s.eta = now.addingTimeInterval(18 * 60)
    s.fraction = 0.34
    s.shape = shape
    s.progress = progress
    s.maneuverAt = progress + distance
    s.fixTime = now.timeIntervalSinceReferenceDate
    s.style = style
    s.destinationName = "Aeropuerto Internacional La Aurora"
    return s
}

render(guidance(.right, 350, "Gira a la derecha en 7a Avenida", progress: 50, style: .night), "moto-1-derecha-noche")
render(guidance(.right, 350, "Gira a la derecha en 7a Avenida", progress: 50, style: .day), "moto-2-derecha-dia")
render(guidance(.left, 80, "Gira a la izquierda en Boulevard Liberación", progress: 1000, style: .night, then: .right), "moto-3-izquierda-luego")
render(guidance(.roundabout, 1200, "En la rotonda, toma la segunda salida hacia Calzada Roosevelt y continúa por el carril central", progress: 420, style: .night), "moto-4-rotonda-texto-largo")
render(guidance(.arrive, 240, "El destino está a la derecha", progress: shape.length - 240, style: .night), "moto-5-llegando")

var rerouting = guidance(.straight, 500, "", progress: 300, style: .night)
rerouting.rerouting = true
rerouting.simulated = true
render(rerouting, "moto-6-recalculando")

var idle = HUDSnapshot()
idle.gpsOk = true
idle.style = .night
render(idle, "moto-7-sin-destino-noche")
idle.style = .day
idle.gpsOk = false
render(idle, "moto-8-sin-destino-dia")

var arrived = HUDSnapshot()
arrived.arrived = true
arrived.style = .night
arrived.destinationName = "Aeropuerto Internacional La Aurora"
render(arrived, "moto-9-llegada")

// Hoja con todos los iconos de maniobra.
let kinds: [ManeuverKind] = [
    .straight, .slightLeft, .left, .sharpLeft, .slightRight, .right, .sharpRight,
    .uTurn, .roundabout, .keepLeft, .keepRight, .arrive, .depart,
]
let cell = 130
let sheet = canvas(cell * 7, cell * 2)
let dark = CGColor(srgbRed: 0.05, green: 0.07, blue: 0.10, alpha: 1)
let blue = CGColor(srgbRed: 0.12, green: 0.48, blue: 1, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
sheet.setFillColor(dark)
sheet.fill(CGRect(x: 0, y: 0, width: cell * 7, height: cell * 2))
for (i, kind) in kinds.enumerated() {
    let rect = CGRect(x: (i % 7) * cell + 10, y: (i / 7) * cell + 10, width: cell - 20, height: cell - 20)
    sheet.addPath(CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil))
    sheet.setFillColor(blue)
    sheet.fillPath()
    HUDIcons.draw(kind, in: rect.insetBy(dx: 12, dy: 12), color: white, hole: blue, ctx: sheet)
}
if let image = sheet.makeImage() {
    save(image, "moto-0-iconos")
}
