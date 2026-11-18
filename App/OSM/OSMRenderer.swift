// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.7: dibujo del mapa de OpenStreetMap para la moto, con CoreGraphics (CPU), como en el video
// de demostración: fondo con degradado, parques, agua, ríos, calles con borde por clase y nombres
// derechos que no tapan la ruta ni las tarjetas. Cada fotograma se dibuja entero (unos pocos ms):
// no hay imágenes guardadas, así que el tema siempre coincide con el del tablero.
import Foundation
import CoreGraphics
import CoreText

/// La cámara del mapa propio: la moto en `anchor`, el rumbo hacia arriba y `metersPerPixel`.
struct OSMCamera {
    let center: GeoPoint
    /// Grados desde el norte que quedan hacia arriba (0 = norte arriba).
    let heading: Double
    let metersPerPixel: Double
    let anchor: CGPoint
    private let kx: Double
    private let ky: Double
    private let c: Double
    private let s: Double

    init(center: GeoPoint, heading: Double, metersPerPixel: Double, anchor: CGPoint) {
        self.center = center
        self.heading = heading
        self.metersPerPixel = metersPerPixel
        self.anchor = anchor
        kx = 111_320 * cos(center.lat * .pi / 180) / metersPerPixel
        ky = 110_574 / metersPerPixel
        c = cos(heading * .pi / 180)
        s = sin(heading * .pi / 180)
    }

    func screen(_ g: GeoPoint) -> CGPoint {
        let dx = (g.lon - center.lon) * kx
        let dy = (g.lat - center.lat) * ky
        return CGPoint(x: anchor.x + CGFloat(dx * c - dy * s), y: anchor.y - CGFloat(dx * s + dy * c))
    }

    func screen(_ p: OSMPoint) -> CGPoint {
        let dx = (Double(p.x) / 1e6 - center.lon) * kx
        let dy = (Double(p.y) / 1e6 - center.lat) * ky
        return CGPoint(x: anchor.x + CGFloat(dx * c - dy * s), y: anchor.y - CGFloat(dx * s + dy * c))
    }

    /// Caja (millonésimas de grado) que cubre `rect` girado, con margen.
    func bounds(_ rect: CGRect) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let radius = corners.map { hypot(Double($0.x - anchor.x), Double($0.y - anchor.y)) }.max() ?? 0
        let r = (radius + 30) * metersPerPixel
        let dLat = r / 110_574 * 1e6
        let dLon = r / (111_320 * cos(center.lat * .pi / 180)) * 1e6
        let x = center.lon * 1e6
        let y = center.lat * 1e6
        return (Int(x - dLon), Int(y - dLat), Int(x + dLon), Int(y + dLat))
    }

    /// Escala según los ajustes: unos 420 m de alto en una zona de 400 px con zoom 1, algo más
    /// lejos con velocidad (zoom automático).
    static func metersPerPixel(zoom: Double, auto: Bool, speed: Double, unit: CGFloat) -> Double {
        var m = 1.05 * zoom
        if auto { m *= 0.9 + min(1, max(0, speed / 22)) * 0.5 }
        return m / Double(max(0.25, unit))
    }
}

/// Colores del mapa propio, de noche y de día (los del video de demostración).
struct OSMPalette {
    let bgTop: CGColor
    let bgBottom: CGColor
    let park: CGColor
    let water: CGColor
    let river: CGColor
    let casing: CGColor
    let roads: [CGColor]          // por clase 1…7
    let label: CGColor
    let halo: CGColor
    let attribution: CGColor

    static func make(night: Bool) -> OSMPalette {
        func c(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
        }
        if night {
            return OSMPalette(bgTop: c(0x111C30), bgBottom: c(0x080F1C), park: c(0x14301F), water: c(0x10284A), river: c(0x173A63),
                              casing: c(0x070C16), roads: [0x232E44, 0x2E3A52, 0x3A4762, 0x44526E, 0x506080, 0x5D6E93, 0x6A7CA3].map { c($0) },
                              label: c(0xB9C4D6), halo: c(0x070C16, 0.9), attribution: c(0xFFFFFF, 0.55))
        }
        return OSMPalette(bgTop: c(0xF1F4F8), bgBottom: c(0xE4E9F0), park: c(0xCFE8D3), water: c(0xA9CDF1), river: c(0x8EBDEB),
                          casing: c(0xC3CCD9), roads: [0xF6F8FB, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFF7DF, 0xFFE9A8, 0xFFE08A].map { c($0) },
                          label: c(0x3B4657), halo: c(0xFFFFFF, 0.92), attribution: c(0x0A1220, 0.55))
    }
}

/// Nombres de calle ya preparados (CoreText es caro de crear y el mismo nombre se dibuja en
/// muchos fotogramas seguidos).
final class OSMLabelCache {
    static let shared = OSMLabelCache()

    struct Label {
        let halo: CTLine
        let fill: CTLine
        let width: CGFloat
    }

    private var items: [String: Label] = [:]
    private var fonts: [CGFloat: CTFont] = [:]
    private let lock = NSLock()

    func label(_ text: String, size: CGFloat, night: Bool, pal: OSMPalette) -> Label {
        let key = "\(night ? 1 : 0)|\(size)|\(text)"
        lock.lock()
        defer { lock.unlock() }
        if let l = items[key] { return l }
        if items.count > 700 { items.removeAll(keepingCapacity: true) }
        let f: CTFont
        if let cached = fonts[size] {
            f = cached
        } else {
            f = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            fonts[size] = f
        }
        let haloAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): pal.halo,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): NSNumber(value: Double(3.2 * 100 / size)),
        ]
        let fillAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): pal.label,
        ]
        let halo = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: haloAttrs))
        let fill = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: fillAttrs))
        let l = Label(halo: halo, fill: fill, width: CGFloat(CTLineGetTypographicBounds(fill, nil, nil, nil)))
        items[key] = l
        return l
    }
}

extension HUDRenderer {
    /// Ancho de cada clase de calle (en el tablero de 800 px).
    static let osmWidths: [CGFloat] = [3, 7, 9, 11, 13, 15, 15]

    /// Fondo del mapa propio: degradado, áreas, ríos y calles. Devuelve cuántas calles dibujó.
    @discardableResult
    func drawOSMBase(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, _ r: CGRect, _ ctx: CGContext) -> Int {
        let pal = OSMPalette.make(night: night)
        let u = k
        // Degradado de fondo.
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [pal.bgTop, pal.bgBottom] as CFArray, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: r)
            ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
            ctx.restoreGState()
        }
        let b = cam.bounds(r)
        let tiles = map.tiles(minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY)
        let limit = r.insetBy(dx: -40 * u, dy: -40 * u)
        // Áreas: parques y agua (rellenas, con la regla par-impar para los huecos).
        for kind in [1, 2] {
            let path = CGMutablePath()
            for t in tiles {
                for a in t.areas where a.kind == kind {
                    for ring in a.rings where ring.count >= 3 {
                        path.move(to: cam.screen(ring[0]))
                        for p in ring.dropFirst() { path.addLine(to: cam.screen(p)) }
                        path.closeSubpath()
                    }
                }
            }
            if !path.isEmpty {
                ctx.addPath(path)
                ctx.setFillColor(kind == 1 ? pal.park : pal.water)
                ctx.fillPath(using: .evenOdd)
            }
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Ríos.
        let rivers = CGMutablePath()
        for t in tiles {
            for l in t.lines where l.points.count >= 2 {
                rivers.move(to: cam.screen(l.points[0]))
                for p in l.points.dropFirst() { rivers.addLine(to: cam.screen(p)) }
            }
        }
        if !rivers.isEmpty {
            ctx.addPath(rivers)
            ctx.setStrokeColor(pal.river)
            ctx.setLineWidth(3 * u)
            ctx.strokePath()
        }
        // Calles: un trazo por clase, primero todos los bordes y luego los rellenos.
        var paths = [CGMutablePath](repeating: CGMutablePath(), count: 8)
        for i in 0..<8 { paths[i] = CGMutablePath() }
        var drawn = 0
        for t in tiles {
            for road in t.roads where road.points.count >= 2 && road.cls >= 1 && road.cls <= 7 {
                var any = false
                var pts: [CGPoint] = []
                pts.reserveCapacity(road.points.count)
                for p in road.points {
                    let v = cam.screen(p)
                    pts.append(v)
                    if limit.contains(v) { any = true }
                }
                if !any && !segmentsCross(pts, limit) { continue }
                let path = paths[road.cls]
                path.move(to: pts[0])
                for v in pts.dropFirst() { path.addLine(to: v) }
                drawn += 1
            }
        }
        for layer in 0..<2 {
            for cls in 1...7 where !paths[cls].isEmpty {
                let w = HUDRenderer.osmWidths[cls - 1] * u
                ctx.addPath(paths[cls])
                if layer == 0 {
                    ctx.setStrokeColor(pal.casing)
                    ctx.setLineWidth(w + 2.4 * u)
                } else {
                    ctx.setStrokeColor(pal.roads[cls - 1])
                    ctx.setLineWidth(w)
                }
                ctx.strokePath()
            }
        }
        return drawn
    }

    /// ¿Algún tramo de la polilínea cruza el rectángulo (aunque ningún punto caiga dentro)?
    private func segmentsCross(_ pts: [CGPoint], _ r: CGRect) -> Bool {
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            if max(a.x, b.x) < r.minX || min(a.x, b.x) > r.maxX || max(a.y, b.y) < r.minY || min(a.y, b.y) > r.maxY { continue }
            return true
        }
        return false
    }

    /// Nombres de las calles, derechos (nunca boca abajo), sin repetirse cerca, sin tapar la ruta
    /// (`avoid`: puntos de la ruta en pantalla) ni las tarjetas (`cards`).
    func drawOSMLabels(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, _ r: CGRect, avoid: [CGPoint], cards: [CGRect], _ ctx: CGContext) {
        if HUDRenderer.hideText { return }
        let pal = OSMPalette.make(night: night)
        let u = k
        let b = cam.bounds(r)
        let tiles = map.tiles(minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY)
        struct Candidate {
            let name: UInt32
            let cls: Int
            let at: CGPoint
            let angle: CGFloat
            let order: Int
        }
        var candidates: [Candidate] = []
        var order = 0
        for t in tiles {
            for road in t.roads where road.name != OSMMapData.noName && road.cls >= 2 && road.points.count >= 2 {
                // Un ancla cada 170 m de la pieza, empezando a 85 m (estables: dependen solo de la calle).
                var acc = 85.0
                for i in 0..<(road.points.count - 1) {
                    let a = road.points[i].geo
                    let bb = road.points[i + 1].geo
                    let len = a.distance(to: bb)
                    var pos = 0.0
                    while acc <= len - pos + 1e-9 && len > 0 {
                        pos += acc
                        acc = 170
                        let f = pos / len
                        let g = GeoPoint(lat: a.lat + (bb.lat - a.lat) * f, lon: a.lon + (bb.lon - a.lon) * f)
                        let v = cam.screen(g)
                        if v.x > r.minX + 30 * u && v.x < r.maxX - 30 * u && v.y > r.minY + 24 * u && v.y < r.maxY - 24 * u {
                            let s0 = cam.screen(a)
                            let s1 = cam.screen(bb)
                            var ang = atan2(s1.y - s0.y, s1.x - s0.x)
                            if ang > .pi / 2 { ang -= .pi }
                            if ang < -.pi / 2 { ang += .pi }
                            candidates.append(Candidate(name: road.name, cls: road.cls, at: v, angle: ang, order: order))
                        }
                        order += 1
                    }
                    acc -= (len - pos)
                }
            }
        }
        candidates.sort { $0.cls != $1.cls ? $0.cls > $1.cls : $0.order < $1.order }
        var placed: [(at: CGPoint, radius: CGFloat, name: UInt32)] = []
        let cache = OSMLabelCache.shared
        for cand in candidates {
            if placed.count >= 11 { break }
            // Primero lo barato (sin medir el texto): junto a la ruta o el mismo nombre cerca.
            if placed.contains(where: { $0.name == cand.name && hypot($0.at.x - cand.at.x, $0.at.y - cand.at.y) < 380 * u }) { continue }
            if avoid.contains(where: { abs($0.x - cand.at.x) < 16 * u && abs($0.y - cand.at.y) < 16 * u && hypot($0.x - cand.at.x, $0.y - cand.at.y) < 16 * u }) { continue }
            let size = (cand.cls >= 4 ? 12.5 : 11.5) * u
            let text = map.name(cand.name)
            guard !text.isEmpty else { continue }
            let label = cache.label(text, size: size, night: night, pal: pal)
            let radius = label.width / 2 + 8 * u
            if cards.contains(where: { $0.insetBy(dx: -radius, dy: -12 * u).contains(cand.at) }) { continue }
            if cand.at.x - radius < r.minX + 4 * u || cand.at.x + radius > r.maxX - 4 * u { continue }
            if placed.contains(where: { hypot($0.at.x - cand.at.x, $0.at.y - cand.at.y) < $0.radius + radius }) { continue }
            placed.append((cand.at, radius, cand.name))
            drawRotatedLabel(label, at: cand.at, angle: cand.angle, size: size, ctx)
        }
    }

    private func drawRotatedLabel(_ label: OSMLabelCache.Label, at p: CGPoint, angle: CGFloat, size: CGFloat, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: -label.width / 2, y: size * 0.35)
        CTLineDraw(label.halo, ctx)
        ctx.textPosition = CGPoint(x: -label.width / 2, y: size * 0.35)
        CTLineDraw(label.fill, ctx)
        ctx.restoreGState()
    }

    /// «© OpenStreetMap», abajo a la izquierda del mapa (lo pide la licencia).
    func drawOSMAttribution(night: Bool, _ r: CGRect, _ ctx: CGContext) {
        if HUDRenderer.hideText { return }
        let pal = OSMPalette.make(night: night)
        let m = measure("© OpenStreetMap", size: 10 * k, bold: false, color: pal.attribution)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: r.minX + 8 * k, y: r.maxY - 7 * k)
        CTLineDraw(m.line, ctx)
        ctx.restoreGState()
    }
}
