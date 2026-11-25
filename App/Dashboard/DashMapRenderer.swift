// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mapa de calles para la moto: la imagen de Apple Maps de fondo y, encima, la ruta, las
// alternativas, la próxima maniobra, la posición y el norte. Todo con CoreGraphics (CPU).
import Foundation
import CoreGraphics

/// Dónde está la moto en este instante: sobre la ruta (avanzando entre fijos del GPS) o, sin
/// ruta, donde dice el GPS.
struct MapPose {
    var here: GeoPoint
    /// Rumbo en grados desde el norte (negativo si no se conoce).
    var heading: Double
    var speed: Double
    var progress: Double?
    var toTurn: Double?

    static func of(_ n: HUDSnapshot, now: Date) -> MapPose? {
        if n.navigating, let shape = n.shape, let geo = n.geo, shape.points.count >= 2 {
            let dt = max(0, min(1.5, now.timeIntervalSinceReferenceDate - n.fixTime))
            let progress = max(0, min(shape.length, n.progress + n.speed * dt))
            var heading = shape.bearing(at: progress, span: 18) * 180 / .pi
            if heading < 0 { heading += 360 }
            return MapPose(
                here: geo.geo(shape.point(at: progress)), heading: heading, speed: n.speed,
                progress: progress, toTurn: max(0, (n.maneuverAt ?? shape.length) - progress)
            )
        }
        if let here = n.here {
            return MapPose(here: here, heading: n.course, speed: n.speed, progress: nil, toTurn: nil)
        }
        return nil
    }
}

extension HUDRenderer {
    /// Dibuja el mapa de calles en `r`. Devuelve false si no hay imagen de calles que sirva:
    /// entonces quien llama usa el dibujo simple de la ruta.
    @discardableResult
    func drawStreetMap(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext, compass: CGRect?) -> Bool {
        guard s.mapSettings.streets, let pose = MapPose.of(s.nav, now: now) else { return false }
        if s.mapSettings.provider == .osm {
            // 0.7: mapa propio de OpenStreetMap (sin imágenes de Apple).
            guard let map = OSMMapData.current else { return false }
            OSMPalette.current = s.mapSettings.osmTheme == .poster
            // Una ruta de Apple (calculada antes de cambiar de mapa) no va sobre este mapa: hasta
            // que llegue la ruta de OpenStreetMap se usa el dibujo simple de la ruta.
            if s.nav.routeFromApple && (s.nav.navigating || !s.nav.previewRoutes.isEmpty) { return false }
            let north = s.mapSettings.northUp || pose.heading < 0
            let cam = OSMCamera(center: pose.here, heading: north ? 0 : pose.heading,
                                metersPerPixel: OSMCamera.metersPerPixel(zoom: s.mapSettings.zoom, auto: s.mapSettings.autoZoom,
                                                                         speed: pose.speed, unit: k),
                                anchor: CGPoint(x: r.midX, y: north ? r.midY : r.minY + r.height * CGFloat(MapCorridor.puckY)))
            ctx.saveGState()
            ctx.clip(to: r)
            guard drawOSMBaseCached(map, cam, night: s.night, r, ctx) > 0 else {
                // Fuera del mapa guardado (otro país o sin calles cerca): el mapa simple.
                ctx.restoreGState()
                return false
            }
            return drawMapOverlay(s, p, now, r, ctx, compass: compass, pose: pose, view: { cam.screen($0) }, osm: (map, cam))
        }
        guard let base = s.map, let image = base.cgImage() else { return false }
        // La imagen cubre el rectángulo sin deformarse (si la proporción no coincide, se recorta).
        let iw = CGFloat(base.pixelWidth)
        let ih = CGFloat(base.pixelHeight)
        let sc = max(r.width / iw, r.height / ih)
        let dw = iw * sc
        let dh = ih * sc
        let ox = r.midX - dw / 2
        let oy = r.midY - dh / 2
        func view(_ g: GeoPoint) -> CGPoint? {
            guard let q = base.project(g) else { return nil }
            return CGPoint(x: ox + q.x * dw, y: oy + q.y * dh)
        }

        ctx.saveGState()
        ctx.clip(to: r)
        func paint(_ img: CGImage, _ b: MapBase, alpha: CGFloat) {
            let s2 = max(r.width / CGFloat(b.pixelWidth), r.height / CGFloat(b.pixelHeight))
            let w2 = CGFloat(b.pixelWidth) * s2
            let h2 = CGFloat(b.pixelHeight) * s2
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: r.midX - w2 / 2, y: r.midY - h2 / 2 + h2)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w2, height: h2))
            ctx.restoreGState()
        }
        // Al pasar de día a noche (o cambiar de estilo) el mapa nuevo aparece fundido sobre el
        // anterior: sin parpadeos ni pantallas negras.
        if s.mapFade < 1, let from = s.mapFrom, let old = from.cgImage() {
            paint(old, from, alpha: 1)
            paint(image, base, alpha: CGFloat(max(0, s.mapFade)))
        } else {
            paint(image, base, alpha: 1)
        }
        return drawMapOverlay(s, p, now, r, ctx, compass: compass, pose: pose, view: view, osm: nil)
    }

    /// Lo que va encima del mapa (de Apple o propio): ruta, alternativas, maniobra, destino,
    /// posición y norte. `view` pasa de coordenadas a la pantalla. Cierra el `saveGState` de quien
    /// llama y devuelve true.
    func drawMapOverlay(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext, compass: CGRect?,
                        pose: MapPose, view: (GeoPoint) -> CGPoint?, osm: (map: OSMMapData, cam: OSMCamera)?) -> Bool {
        let u = k
        var routeScreen: [CGPoint] = []
        let n = s.nav
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Estilo de la línea de la ruta.
        let style = s.mapSettings.routeStyle
        let lineWidth: CGFloat = style == .thin ? 9 : (style == .highContrast ? 16 : 15)
        let casingWidth: CGFloat = style == .thin ? 15 : (style == .highContrast ? 24 : 23)
        let halo: CGColor? = style == .highContrast
            ? (s.night ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85) : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)) : nil
        func strokeRoute(_ line: CGPath, fade: CGFloat) {
            ctx.saveGState()
            ctx.setAlpha(fade)
            if let halo = halo {
                ctx.addPath(line)
                ctx.setStrokeColor(halo)
                ctx.setLineWidth(31 * u)
                ctx.strokePath()
            } else {
                // 0.6.3: resplandor suave alrededor de la ruta, como en la referencia.
                ctx.addPath(line)
                ctx.setStrokeColor(p.routeGlow)
                ctx.setLineWidth((casingWidth + 11) * u)
                ctx.strokePath()
            }
            ctx.addPath(line)
            ctx.setStrokeColor(p.routeCasing)
            ctx.setLineWidth(casingWidth * u)
            ctx.strokePath()
            ctx.addPath(line)
            ctx.setStrokeColor(p.route)
            ctx.setLineWidth(lineWidth * u)
            ctx.strokePath()
            // Brillo en el centro de la línea (tubo de luz).
            ctx.addPath(line)
            ctx.setStrokeColor(p.routeLight)
            ctx.setLineWidth(max(2, lineWidth * 0.27) * u)
            ctx.strokePath()
            ctx.restoreGState()
        }
        let limit = r.insetBy(dx: -r.width, dy: -r.height)
        func path(_ points: [GeoPoint]) -> CGPath? {
            let line = CGMutablePath()
            var open = false
            var count = 0
            for g in points {
                guard let v = view(g), limit.contains(v) else {
                    open = false
                    continue
                }
                if open { line.addLine(to: v) } else { line.move(to: v) }
                open = true
                count += 1
            }
            return count >= 2 ? line : nil
        }

        if n.navigating, let shape = n.shape, let geo = n.geo, let progress = pose.progress {
            // Alternativas: grises y debajo de la ruta elegida.
            for alt in n.alternates where alt.count >= 2 {
                if let line = path(alt.map { geo.geo($0) }) {
                    ctx.addPath(line)
                    ctx.setStrokeColor(alpha(p.routeCasing, 0.55))
                    ctx.setLineWidth(15 * u)
                    ctx.strokePath()
                    ctx.addPath(line)
                    ctx.setStrokeColor(alpha(p.dim, 0.9))
                    ctx.setLineWidth(9 * u)
                    ctx.strokePath()
                }
            }
            func stretch(_ a: Double, _ b: Double) -> [GeoPoint] {
                guard b > a else { return [] }
                // Los puntos de la ruta y, en los tramos largos, uno cada 40 m. En una recta larga
                // el siguiente punto de la ruta puede quedar muy fuera de la imagen (sobre todo en
                // las guardadas, que son planas); se saltaba y la línea no se veía por delante.
                var marks: [Double] = [a]
                let first = shape.segmentIndex(at: a) + 1
                let last = shape.segmentIndex(at: b)
                if first <= last {
                    for i in first...last where shape.cumulative[i] > a && shape.cumulative[i] < b {
                        marks.append(shape.cumulative[i])
                    }
                }
                marks.append(b)
                var out: [GeoPoint] = []
                out.reserveCapacity(marks.count + 32)
                for j in marks.indices {
                    if j > 0 {
                        let gap = marks[j] - marks[j - 1]
                        if gap > 40 {
                            let pieces = Int((gap / 40).rounded(.up))
                            for k in 1..<pieces {
                                out.append(geo.geo(shape.point(at: marks[j - 1] + gap * Double(k) / Double(pieces))))
                            }
                        }
                    }
                    out.append(geo.geo(shape.point(at: marks[j])))
                }
                return out
            }
            let from = max(0, progress - 200)
            let to = min(shape.length, progress + 6000)
            // Lo ya recorrido, tenue y sin borde; lo que falta, grueso y con borde.
            if progress - from > 2, let done = path(stretch(from, progress)) {
                ctx.addPath(done)
                ctx.setStrokeColor(alpha(p.route, 0.35))
                ctx.setLineWidth(11 * u)
                ctx.strokePath()
            }
            let aheadPoints = stretch(progress, to)
            if let ahead = path(aheadPoints) {
                strokeRoute(ahead, fade: CGFloat(min(1, max(0, s.routeFade))))
                if osm != nil { routeScreen = aheadPoints.compactMap(view) }
            }
            // Próxima maniobra: flecha blanca sobre la ruta que dibuja el giro (cuando se acerca).
            if let at = n.maneuverAt, at > progress + 4, at - progress < 700 {
                let a = max(progress, at - 32)
                let b = min(shape.length, at + 30)
                if b > a + 5, let arrow = path(stretch(a, b)),
                   let tipA = view(geo.geo(shape.point(at: max(a, b - 9)))), let tip = view(geo.geo(shape.point(at: b))) {
                    ctx.addPath(arrow)
                    ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
                    ctx.setLineWidth(13 * u)
                    ctx.strokePath()
                    ctx.addPath(arrow)
                    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                    ctx.setLineWidth(8 * u)
                    ctx.strokePath()
                    let ang = atan2(tip.y - tipA.y, tip.x - tipA.x)
                    let size = 15 * u
                    ctx.saveGState()
                    ctx.translateBy(x: tip.x, y: tip.y)
                    ctx.rotate(by: ang)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: size * 0.9, y: 0))
                    ctx.addLine(to: CGPoint(x: -size * 0.4, y: -size * 0.8))
                    ctx.addLine(to: CGPoint(x: -size * 0.4, y: size * 0.8))
                    ctx.closePath()
                    ctx.setLineWidth(4 * u)
                    ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                    ctx.drawPath(using: .fillStroke)
                    ctx.restoreGState()
                }
            } else if let at = n.maneuverAt, at > progress + 4, let m = view(geo.geo(shape.point(at: at))), r.contains(m) {
                ctx.setFillColor(p.onAccent)
                ctx.fillEllipse(in: CGRect(x: m.x - 12 * u, y: m.y - 12 * u, width: 24 * u, height: 24 * u))
                ctx.setFillColor(p.accent)
                ctx.fillEllipse(in: CGRect(x: m.x - 7 * u, y: m.y - 7 * u, width: 14 * u, height: 14 * u))
            }
            // Destino.
            if let d = view(geo.geo(shape.point(at: shape.length))), r.contains(d) {
                drawFlag(at: d, u: u, p, ctx)
            }
        }

        // Antes de empezar: las rutas propuestas (la elegida en azul, las demás en gris).
        if !n.navigating && !n.previewRoutes.isEmpty {
            for (i, route) in n.previewRoutes.enumerated() where i != n.previewSelected {
                if let line = path(route) {
                    ctx.addPath(line)
                    ctx.setStrokeColor(alpha(p.routeCasing, 0.55))
                    ctx.setLineWidth(15 * u)
                    ctx.strokePath()
                    ctx.addPath(line)
                    ctx.setStrokeColor(alpha(p.dim, 0.9))
                    ctx.setLineWidth(9 * u)
                    ctx.strokePath()
                }
            }
            if n.previewRoutes.indices.contains(n.previewSelected) {
                let chosen = n.previewRoutes[n.previewSelected]
                if let line = path(chosen) {
                    strokeRoute(line, fade: 1)
                    if osm != nil { routeScreen = chosen.compactMap(view) }
                }
                if let last = chosen.last, let d = view(last), r.contains(d) { drawFlag(at: d, u: u, p, ctx) }
            }
        }
        // Guía en otra app: solo el destino.
        if let ext = s.external, !n.navigating, let d = view(ext.destination), r.contains(d) {
            drawFlag(at: d, u: u, p, ctx)
        }

        // 0.7: nombres de las calles (sin tapar la ruta ni las tarjetas) y el aviso de la licencia.
        if let o = osm {
            drawOSMLabels(o.map, o.cam, night: s.night, r, avoid: routeScreen, cards: mapAvoid, ctx)
            drawOSMAttribution(night: s.night, r, ctx)
        }

        // Posición: flecha si se conoce el rumbo, punto si no.
        if let c = view(pose.here) {
            var angle: CGFloat?
            if pose.heading >= 0, let a = view(pose.here.moved(15, bearing: pose.heading)) {
                angle = atan2(a.x - c.x, -(a.y - c.y))
            }
            drawPuck(at: c, angle: angle, u: u, p, ctx)
        }

        // Norte, calculado con la propia imagen (vale igual con el mapa girado o inclinado).
        if let box = compass, let c = view(pose.here), let northPoint = view(pose.here.moved(40, bearing: 0)) {
            let a = atan2(northPoint.x - c.x, -(northPoint.y - c.y))
            drawCompass(in: box, angle: a, p, ctx)
        }
        ctx.restoreGState()
        return true
    }

    /// Indicador de posición (0.6.3: el de la referencia, igual en el mapa simple).
    func drawPuck(at c: CGPoint, angle: CGFloat?, u: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        positionMark(at: c, angle: angle, u: u, p, ctx)
    }

    /// Destino (0.6.3): marcador rojo con punto blanco y su sombra en el suelo, como en la
    /// referencia.
    func drawFlag(at d: CGPoint, u: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(p.pin.copy(alpha: 0.32) ?? p.pin)
        ctx.fillEllipse(in: CGRect(x: d.x - 10 * u, y: d.y - 4 * u, width: 20 * u, height: 8 * u))
        ctx.setFillColor(p.onAccent)
        ctx.fillEllipse(in: CGRect(x: d.x - 3 * u, y: d.y - 2 * u, width: 6 * u, height: 4 * u))
        let head = CGPoint(x: d.x, y: d.y - 22 * u)
        let r = 10.5 * u
        let pin = CGMutablePath()
        pin.move(to: CGPoint(x: d.x, y: d.y - 1 * u))
        pin.addLine(to: CGPoint(x: head.x - r * 0.84, y: head.y + r * 0.55))
        pin.addArc(center: head, radius: r, startAngle: .pi * 0.82, endAngle: .pi * 0.18, clockwise: false)
        pin.closeSubpath()
        ctx.setShadow(offset: .zero, blur: 5 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        ctx.addPath(pin)
        ctx.setFillColor(p.pin)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(pin)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setLineWidth(1.6 * u)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: head.x - 4 * u, y: head.y - 4 * u, width: 8 * u, height: 8 * u))
        ctx.restoreGState()
    }

    /// Brújula (0.6.3): círculo de vidrio como el resto de tarjetas, con la aguja roja hacia el
    /// norte. `angle`: radianes desde arriba.
    func drawCompass(in box: CGRect, angle: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        let c = CGPoint(x: box.midX, y: box.midY)
        let rad = min(box.width, box.height) / 2
        glassCard(CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2), radius: rad, p, ctx)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: -rad * 0.68))
        ctx.addLine(to: CGPoint(x: rad * 0.26, y: 0))
        ctx.addLine(to: CGPoint(x: -rad * 0.26, y: 0))
        ctx.closePath()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1))
        ctx.fillPath()
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: rad * 0.68))
        ctx.addLine(to: CGPoint(x: rad * 0.26, y: 0))
        ctx.addLine(to: CGPoint(x: -rad * 0.26, y: 0))
        ctx.closePath()
        ctx.setFillColor(p.text.copy(alpha: 0.82) ?? p.text)
        ctx.fillPath()
        ctx.setFillColor(p.dark ? CGColor(srgbRed: 0.05, green: 0.1, blue: 0.19, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: -rad * 0.1, y: -rad * 0.1, width: rad * 0.2, height: rad * 0.2))
        ctx.restoreGState()
    }
}
