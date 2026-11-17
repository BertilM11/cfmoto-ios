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
        guard s.mapSettings.streets, let base = s.map, let image = base.cgImage(),
              let pose = MapPose.of(s.nav, now: now) else { return false }
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
        let u = k

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.saveGState()
        ctx.translateBy(x: ox, y: oy + dh)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: dw, height: dh))
        ctx.restoreGState()

        let n = s.nav
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
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
                var out = [geo.geo(shape.point(at: a))]
                let first = shape.segmentIndex(at: a) + 1
                let last = shape.segmentIndex(at: b)
                if first <= last {
                    for i in first...last { out.append(geo.geo(shape.points[i])) }
                }
                out.append(geo.geo(shape.point(at: b)))
                return out
            }
            let from = max(0, progress - 200)
            let to = min(shape.length, progress + 6000)
            if let whole = path(stretch(from, to)) {
                ctx.addPath(whole)
                ctx.setStrokeColor(p.routeCasing)
                ctx.setLineWidth(23 * u)
                ctx.strokePath()
                ctx.addPath(whole)
                ctx.setStrokeColor(p.route)
                ctx.setLineWidth(15 * u)
                ctx.strokePath()
            }
            if progress - from > 2, let done = path(stretch(from, progress)) {
                ctx.addPath(done)
                ctx.setStrokeColor(p.routeDone)
                ctx.setLineWidth(15 * u)
                ctx.strokePath()
            }
            // Próxima maniobra.
            if let at = n.maneuverAt, at > progress + 4, let m = view(geo.geo(shape.point(at: at))), r.contains(m) {
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

    /// Indicador de posición: halo, borde blanco y flecha del color de la ruta.
    func drawPuck(at c: CGPoint, angle: CGFloat?, u: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(alpha(p.accent, 0.22))
        ctx.fillEllipse(in: CGRect(x: c.x - 30 * u, y: c.y - 30 * u, width: 60 * u, height: 60 * u))
        guard let angle = angle else {
            ctx.setFillColor(p.onAccent)
            ctx.fillEllipse(in: CGRect(x: c.x - 13 * u, y: c.y - 13 * u, width: 26 * u, height: 26 * u))
            ctx.setFillColor(p.accent)
            ctx.fillEllipse(in: CGRect(x: c.x - 9 * u, y: c.y - 9 * u, width: 18 * u, height: 18 * u))
            ctx.restoreGState()
            return
        }
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        func arrow(_ s: CGFloat) -> CGPath {
            let a = CGMutablePath()
            a.move(to: CGPoint(x: 0, y: -22 * s))
            a.addLine(to: CGPoint(x: 16 * s, y: 16 * s))
            a.addLine(to: CGPoint(x: 0, y: 7 * s))
            a.addLine(to: CGPoint(x: -16 * s, y: 16 * s))
            a.closeSubpath()
            return a
        }
        ctx.setShadow(offset: .zero, blur: 6 * u, color: alpha(CGColor(gray: 0, alpha: 1), 0.6))
        ctx.addPath(arrow(u * 1.12))
        ctx.setFillColor(p.onAccent)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(arrow(u * 0.78))
        ctx.setFillColor(p.accent)
        ctx.fillPath()
        ctx.restoreGState()
    }

    func drawFlag(at d: CGPoint, u: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(p.onAccent)
        ctx.fillEllipse(in: CGRect(x: d.x - 13 * u, y: d.y - 13 * u, width: 26 * u, height: 26 * u))
        ctx.setFillColor(p.good)
        ctx.fillEllipse(in: CGRect(x: d.x - 9 * u, y: d.y - 9 * u, width: 18 * u, height: 18 * u))
        ctx.restoreGState()
    }

    /// Brújula: círculo con la punta roja hacia el norte. `angle`: radianes desde arriba.
    func drawCompass(in box: CGRect, angle: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        let c = CGPoint(x: box.midX, y: box.midY)
        let rad = min(box.width, box.height) / 2
        ctx.saveGState()
        ctx.setFillColor(alpha(p.background, 0.86))
        ctx.fillEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: -rad * 0.72))
        ctx.addLine(to: CGPoint(x: rad * 0.3, y: 0))
        ctx.addLine(to: CGPoint(x: -rad * 0.3, y: 0))
        ctx.closePath()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1))
        ctx.fillPath()
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: rad * 0.72))
        ctx.addLine(to: CGPoint(x: rad * 0.3, y: 0))
        ctx.addLine(to: CGPoint(x: -rad * 0.3, y: 0))
        ctx.closePath()
        ctx.setFillColor(p.dim)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
