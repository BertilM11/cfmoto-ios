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
    /// El color de en medio del degradado (fondo de la imagen guardada del mapa).
    let bgMid: CGColor
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
            return OSMPalette(bgTop: c(0x111C30), bgBottom: c(0x080F1C), bgMid: c(0x0D1626), park: c(0x14301F), water: c(0x10284A), river: c(0x173A63),
                              casing: c(0x070C16), roads: [0x232E44, 0x2E3A52, 0x3A4762, 0x44526E, 0x506080, 0x5D6E93, 0x6A7CA3].map { c($0) },
                              label: c(0xB9C4D6), halo: c(0x070C16, 0.9), attribution: c(0xFFFFFF, 0.55))
        }
        return OSMPalette(bgTop: c(0xF1F4F8), bgBottom: c(0xE4E9F0), bgMid: c(0xEBEFF4), park: c(0xCFE8D3), water: c(0xA9CDF1), river: c(0x8EBDEB),
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
        /// El nombre ya dibujado con su borde (se pega girado en cada fotograma: es mucho más
        /// barato que volver a dibujar las letras).
        let image: CGImage?
        let ascent: CGFloat
        let descent: CGFloat
        let pad: CGFloat
    }

    /// Dibujar los nombres desde su imagen (las pruebas comparan con el dibujo de las letras).
    static var useImages = true

    /// Un sitio posible para el nombre de una calle (uno cada 170 m de cada calle con nombre).
    struct Anchor {
        let name: UInt32
        let cls: Int
        let at: GeoPoint
        /// Extremos del tramo, para girar el nombre como la calle.
        let a: GeoPoint
        let b: GeoPoint
    }

    private var items: [String: Label] = [:]
    private var fonts: [CGFloat: CTFont] = [:]
    private var anchorTiles: [Int64: [Anchor]] = [:]
    private let lock = NSLock()

    /// Los sitios para nombres de un cuadro (se calculan una vez por cuadro, no en cada fotograma).
    func anchors(_ t: OSMTile) -> [Anchor] {
        let key = Int64(t.row) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: t.col)))
        lock.lock()
        if let cached = anchorTiles[key] {
            lock.unlock()
            return cached
        }
        if anchorTiles.count > 300 { anchorTiles.removeAll(keepingCapacity: true) }
        lock.unlock()
        var out: [Anchor] = []
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
                    out.append(Anchor(name: road.name, cls: road.cls,
                                      at: GeoPoint(lat: a.lat + (bb.lat - a.lat) * f, lon: a.lon + (bb.lon - a.lon) * f), a: a, b: bb))
                }
                acc -= (len - pos)
            }
        }
        lock.lock()
        if anchorTiles.count > 400 { anchorTiles.removeAll(keepingCapacity: true) }
        anchorTiles[key] = out
        lock.unlock()
        return out
    }

    /// 0.9.0: suelta todo (aviso de memoria de iOS o la app pasa a segundo plano).
    func trim() {
        lock.lock()
        items.removeAll()
        anchorTiles.removeAll()
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func label(_ text: String, size: CGFloat, night: Bool, pal: OSMPalette) -> Label {
        let key = "\(night ? 1 : 0)|\(size)|\(text)"
        lock.lock()
        defer { lock.unlock() }
        if let l = items[key] { return l }
        // 0.9.0: sin límite crecía todo el viaje (una imagen por calle vista); se vacía al pasar
        // de 600 nombres (se vuelven a preparar los que sigan a la vista).
        if items.count > 600 { items.removeAll(keepingCapacity: true) }
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
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(fill, &ascent, &descent, nil))
        let pad = ceil(size * 0.2) + 2
        var image: CGImage?
        let w = Int(ceil(width + 2 * pad))
        let h = Int(ceil(ascent + descent + 2 * pad))
        if w > 0, h > 0, w < 2000, h < 400,
           let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            // Contexto normal (y hacia arriba): la línea base queda a pad + descent del borde de abajo.
            c.textPosition = CGPoint(x: pad, y: pad + descent)
            CTLineDraw(halo, c)
            c.textPosition = CGPoint(x: pad, y: pad + descent)
            CTLineDraw(fill, c)
            image = c.makeImage()
        }
        if items.count > 360 { items.removeAll(keepingCapacity: true) }
        let l = Label(halo: halo, fill: fill, width: width, image: image, ascent: ascent, descent: descent, pad: pad)
        items[key] = l
        return l
    }
}

extension HUDRenderer {
    /// Ancho de cada clase de calle (en el tablero de 800 px).
    static let osmWidths: [CGFloat] = [3, 7, 9, 11, 13, 15, 15]

    /// Fondo del mapa propio dibujado directamente: degradado, áreas, ríos y calles. Devuelve
    /// cuántas calles dibujó. (La app usa `drawOSMBaseCached`, que reutiliza una imagen.)
    @discardableResult
    func drawOSMBase(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, _ r: CGRect, _ ctx: CGContext) -> Int {
        HUDRenderer.paintOSMBase(map, cam, night: night, r, ctx, unit: k, gradient: true)
    }

    /// Fondo del mapa propio con la imagen guardada (girada y movida en cada fotograma).
    @discardableResult
    func drawOSMBaseCached(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, _ r: CGRect, _ ctx: CGContext) -> Int {
        guard OSMBaseCache.enabled else { return drawOSMBase(map, cam, night: night, r, ctx) }
        return osmBaseCache.draw(map, cam, night: night, unit: k, r, ctx)
    }

    static func paintOSMBase(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, _ r: CGRect, _ ctx: CGContext,
                             unit u: CGFloat, gradient: Bool) -> Int {
        let pal = OSMPalette.make(night: night)
        if gradient, let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [pal.bgTop, pal.bgBottom] as CFArray, locations: [0, 1]) {
            // Degradado de fondo.
            ctx.saveGState()
            ctx.clip(to: r)
            ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
            ctx.restoreGState()
        } else {
            ctx.setFillColor(pal.bgMid)
            ctx.fill(r)
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
                if !any && !HUDRenderer.segmentsCross(pts, limit) { continue }
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
    private static func segmentsCross(_ pts: [CGPoint], _ r: CGRect) -> Bool {
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
        let labelCache = OSMLabelCache.shared
        for t in tiles {
            for an in labelCache.anchors(t) {
                let v = cam.screen(an.at)
                if v.x > r.minX + 30 * u && v.x < r.maxX - 30 * u && v.y > r.minY + 24 * u && v.y < r.maxY - 24 * u {
                    let s0 = cam.screen(an.a)
                    let s1 = cam.screen(an.b)
                    var ang = atan2(s1.y - s0.y, s1.x - s0.x)
                    if ang > .pi / 2 { ang -= .pi }
                    if ang < -.pi / 2 { ang += .pi }
                    candidates.append(Candidate(name: an.name, cls: an.cls, at: v, angle: ang, order: order))
                }
                order += 1
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
            // El nombre ocupa una línea girada: se comprueban cinco puntos a lo largo de ella, para
            // que ningún extremo quede debajo de una tarjeta ni fuera de la pantalla.
            let reach = label.width / 2 + 4 * u
            let dx = cos(cand.angle) * reach
            let dy = sin(cand.angle) * reach
            let along = [-1.0, -0.5, 0, 0.5, 1.0].map { CGPoint(x: cand.at.x + dx * CGFloat($0), y: cand.at.y + dy * CGFloat($0)) }
            if cards.contains(where: { card in
                let near = card.insetBy(dx: -8 * u, dy: -8 * u)
                return along.contains { near.contains($0) }
            }) { continue }
            let inside = r.insetBy(dx: 4 * u, dy: 6 * u)
            if !along.allSatisfy({ inside.contains($0) }) { continue }
            if placed.contains(where: { hypot($0.at.x - cand.at.x, $0.at.y - cand.at.y) < $0.radius + radius }) { continue }
            placed.append((cand.at, radius, cand.name))
            drawRotatedLabel(label, at: cand.at, angle: cand.angle, size: size, ctx)
        }
    }

    private func drawRotatedLabel(_ label: OSMLabelCache.Label, at p: CGPoint, angle: CGFloat, size: CGFloat, _ ctx: CGContext) {
        if OSMLabelCache.useImages, let img = label.image {
            // La línea base va 0,35·tamaño por debajo del punto, como al dibujar las letras.
            let baseline = size * 0.35
            let top = baseline - label.ascent - label.pad
            let w = CGFloat(img.width)
            let h = CGFloat(img.height)
            ctx.saveGState()
            if abs(angle) > 0.01 {
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: angle)
                ctx.interpolationQuality = .medium
                ctx.translateBy(x: -label.width / 2 - label.pad, y: top + h)
            } else {
                // Sin girar, en píxeles enteros: tan nítido como las letras dibujadas.
                ctx.translateBy(x: (p.x - label.width / 2 - label.pad).rounded(), y: (p.y + top + h).rounded())
            }
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
            return
        }
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
        // 0.9.0: el emblema va encima de la señal de velocidad (o de la brújula); aquí solo si no
        // cupo allí.
        if brandSpot == nil {
            drawBrandMark(color: pal.attribution, x: r.minX + 8 * k + m.width + 8 * k, baseline: r.maxY - 7 * k, ctx)
        }
    }

    /// 0.9.0: tamaño del emblema de BERL.
    var brandSize: CGSize {
        let h = 26 * k
        return CGSize(width: BrandMark.width(forHeight: h), height: h)
    }

    /// 0.9.0: sitio del emblema justo encima de `anchor` (la señal de velocidad o la brújula),
    /// o debajo si `anchor` está en la mitad de arriba; nil si no cabe sin tapar nada.
    func brandRect(above anchor: CGRect?, zone: CGRect, busy: [CGRect]) -> CGRect? {
        guard let a = anchor, !a.isEmpty, BrandMark.mask != nil else { return nil }
        let size = brandSize
        let gap = 6 * k
        let up = a.midY > zone.midY
        var x = a.midX - size.width / 2
        x = min(max(x, zone.minX + 4 * k), zone.maxX - size.width - 4 * k)
        let y = up ? a.minY - gap - size.height : a.maxY + gap
        let cand = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        guard zone.contains(cand) else { return nil }
        if busy.contains(where: { !$0.isEmpty && $0.intersects(cand.insetBy(dx: -2 * k, dy: -2 * k)) }) { return nil }
        return cand
    }

    /// 0.9.0: dibuja el emblema en `rect` con el color tenue del aviso de la licencia.
    func drawBrand(in rect: CGRect, night: Bool, _ ctx: CGContext) {
        let pal = OSMPalette.make(night: night)
        drawBrandMark(color: pal.attribution, x: rect.minX, baseline: rect.maxY - 2 * k, ctx)
    }

    /// 0.7.1: el emblema de BERL, pequeño y tenue, justo después de «© OpenStreetMap» (esa
    /// esquina ya queda libre de tarjetas). Mismo color que el aviso de la licencia.
    func drawBrandMark(color: CGColor, x: CGFloat, baseline: CGFloat, _ ctx: CGContext) {
        guard let mask = BrandMark.mask else { return }
        let h = 26 * k   // 0.7.6: más grande (antes 17)
        let w = BrandMark.width(forHeight: h)
        let rect = CGRect(x: x.rounded(), y: (baseline + 2 * k - h).rounded(), width: w, height: h)
        ctx.saveGState()
        // El contexto tiene la «y» hacia abajo: se da vuelta para que la máscara quede derecha.
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        let local = CGRect(origin: .zero, size: rect.size)
        ctx.interpolationQuality = .high
        ctx.clip(to: local, mask: mask)
        ctx.setFillColor(color)
        ctx.fill(local)
        ctx.restoreGState()
    }
}

/// 0.7: el fondo del mapa propio (parques, agua, ríos y calles) dibujado una vez en una imagen
/// con el norte arriba, más grande que lo que se ve, y reutilizado girado y movido en cada
/// fotograma. Se rehace en segundo plano antes de que la moto llegue a su borde, o si cambia el
/// zoom; si cambia el tema o se salta lejos, se rehace en el momento. Así cada fotograma cuesta
/// poco aunque haya muchas calles (los nombres se siguen dibujando en cada fotograma, derechos).
final class OSMBaseCache {
    struct Entry {
        let image: CGImage
        let center: GeoPoint
        let mpp: Double
        let night: Bool
        let unit: CGFloat
        /// Medio lado de la imagen, en puntos.
        let half: CGFloat
        let drawn: Int
    }

    /// Las pruebas pueden apagarlo para comparar con el dibujo directo.
    static var enabled = true
    /// Suavizado al girar la imagen (las pruebas comparan calidades y tiempos).
    static var interpolation: CGInterpolationQuality = .medium
    /// Imágenes rehechas (para el diagnóstico y las pruebas).
    private(set) var builds = 0
    private var entry: Entry?
    private var building = false
    private let lock = NSLock()
    private static let queue = DispatchQueue(label: "cfmoto.osm.fondo", qos: .userInitiated)

    /// Dibuja el fondo en `r` para la cámara `cam`. Devuelve cuántas calles tiene la imagen.
    func draw(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, unit: CGFloat, _ r: CGRect, _ ctx: CGContext) -> Int {
        // Lo que tiene que cubrir la imagen: el rectángulo girado alrededor de la moto.
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        let need = (corners.map { hypot($0.x - cam.anchor.x, $0.y - cam.anchor.y) }.max() ?? 0) + 6 * unit
        lock.lock()
        let current = entry
        lock.unlock()
        var use: Entry?
        if let e = current, e.night == night, e.unit == unit {
            let scale = e.mpp / cam.metersPerPixel
            let off = OSMBaseCache.offset(of: cam.center, from: e.center, mpp: cam.metersPerPixel)
            let reach = e.half * CGFloat(scale) - hypot(off.x, off.y)
            if scale > 0.8 && scale < 1.25 && reach >= need {
                use = e
                // Queda poco margen o cambió el zoom: se prepara otra en segundo plano.
                let margin = e.half * CGFloat(scale) - need
                if reach < need + margin * 0.45 || abs(scale - 1) > 0.08 {
                    rebuild(map, cam, night: night, unit: unit, need: need, ctx: ctx)
                }
            }
        }
        if use == nil {
            use = OSMBaseCache.render(map, center: cam.center, mpp: cam.metersPerPixel, night: night, unit: unit,
                                      half: (need * 1.35).rounded(.up), like: ctx)
            lock.lock()
            if let u = use { entry = u }
            builds += 1
            lock.unlock()
        }
        guard let e = use else {
            return HUDRenderer.paintOSMBase(map, cam, night: night, r, ctx, unit: unit, gradient: true)
        }
        let off = OSMBaseCache.offset(of: cam.center, from: e.center, mpp: cam.metersPerPixel)
        let scale = CGFloat(e.mpp / cam.metersPerPixel)
        let angle = -CGFloat(cam.heading * .pi / 180)
        // Solo la parte de la imagen que cae en pantalla (girar la imagen entera cuesta más).
        let cosA = cos(-angle)
        let sinA = sin(-angle)
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for c in corners {
            let dx = c.x - cam.anchor.x
            let dy = c.y - cam.anchor.y
            let rx = dx * cosA - dy * sinA + off.x
            let ry = dx * sinA + dy * cosA - off.y
            let ix = e.half + rx / scale
            let iy = e.half + ry / scale
            minX = min(minX, ix)
            minY = min(minY, iy)
            maxX = max(maxX, ix)
            maxY = max(maxY, iy)
        }
        let side = 2 * e.half
        let x0 = floor(max(0, minX - 2))
        let y0 = floor(max(0, minY - 2))
        let x1 = ceil(min(side, maxX + 2))
        let y1 = ceil(min(side, maxY + 2))
        let crop = CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
        let part = crop.width > 4 && crop.height > 4 ? (e.image.cropping(to: crop) ?? e.image) : e.image
        let at = part === e.image ? CGRect(x: 0, y: 0, width: side, height: side) : crop
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.interpolationQuality = OSMBaseCache.interpolation
        // Imagen (norte arriba, centrada en e.center) → pantalla (rumbo hacia arriba, la moto en anchor).
        ctx.translateBy(x: cam.anchor.x, y: cam.anchor.y)
        ctx.rotate(by: angle)
        ctx.translateBy(x: -off.x, y: off.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -e.half, y: -e.half)
        // El contexto tiene la y hacia abajo: la imagen se voltea para verse derecha.
        ctx.translateBy(x: at.minX, y: at.minY + at.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: at.width, height: at.height))
        ctx.restoreGState()
        return e.drawn
    }

    /// Metros al este y al norte de `p` desde `c`, en puntos de pantalla con `mpp`.
    private static func offset(of p: GeoPoint, from c: GeoPoint, mpp: Double) -> CGPoint {
        let east = (p.lon - c.lon) * 111_320 * cos(c.lat * .pi / 180)
        let north = (p.lat - c.lat) * 110_574
        return CGPoint(x: east / mpp, y: north / mpp)
    }

    private func rebuild(_ map: OSMMapData, _ cam: OSMCamera, night: Bool, unit: CGFloat, need: CGFloat, ctx: CGContext) {
        lock.lock()
        if building {
            lock.unlock()
            return
        }
        building = true
        lock.unlock()
        // La imagen nueva se centra un poco por delante, hacia donde va la moto.
        let half = (need * 1.35).rounded(.up)
        let ahead = Double(half - need) * 0.45 * cam.metersPerPixel
        let center = cam.heading != 0 ? cam.center.moved(ahead, bearing: cam.heading) : cam.center
        let mpp = cam.metersPerPixel
        let space = ctx.colorSpace
        OSMBaseCache.queue.async { [weak self] in
            let made = OSMBaseCache.render(map, center: center, mpp: mpp, night: night, unit: unit, half: half, space: space)
            guard let self = self else { return }
            self.lock.lock()
            if let made = made { self.entry = made }
            self.builds += 1
            self.building = false
            self.lock.unlock()
        }
    }

    private static func render(_ map: OSMMapData, center: GeoPoint, mpp: Double, night: Bool, unit: CGFloat, half: CGFloat,
                               like ctx: CGContext) -> Entry? {
        render(map, center: center, mpp: mpp, night: night, unit: unit, half: half, space: ctx.colorSpace)
    }

    private static func render(_ map: OSMMapData, center: GeoPoint, mpp: Double, night: Bool, unit: CGFloat, half: CGFloat,
                               space: CGColorSpace?) -> Entry? {
        let side = Int(2 * half)
        guard side > 0, side < 6000 else { return nil }
        let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        // Como el tablero: origen arriba a la izquierda y la y hacia abajo.
        c.translateBy(x: 0, y: CGFloat(side))
        c.scaleBy(x: 1, y: -1)
        let cam = OSMCamera(center: center, heading: 0, metersPerPixel: mpp, anchor: CGPoint(x: half, y: half))
        let drawn = HUDRenderer.paintOSMBase(map, cam, night: night, CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)), c,
                                             unit: unit, gradient: false)
        guard let image = c.makeImage() else { return nil }
        return Entry(image: image, center: center, mpp: mpp, night: night, unit: unit, half: half, drawn: drawn)
    }
}
