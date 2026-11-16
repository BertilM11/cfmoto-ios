// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Dibujo de la pantalla de navegación para la moto. Usa solo CoreGraphics y CoreText (CPU),
// sin UIKit ni GPU: así puede seguir dibujando con la app en segundo plano, y además se puede
// compilar en macOS para revisar el resultado en la compilación automática.
import Foundation
import CoreGraphics
import CoreText

struct HUDPalette {
    let background: CGColor
    let panel: CGColor
    let text: CGColor
    let dim: CGColor
    let accent: CGColor
    let onAccent: CGColor
    let route: CGColor
    let routeCasing: CGColor
    let routeDone: CGColor
    let warn: CGColor
    let good: CGColor
    let line: CGColor

    private static func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let night = HUDPalette(
        background: c(0x06090E),
        panel: c(0x0E151F),
        text: c(0xFFFFFF),
        dim: c(0x98A5B9),
        accent: c(0x1F7AFF),
        onAccent: c(0xFFFFFF),
        route: c(0x4C9AFF),
        routeCasing: c(0x0A2550),
        routeDone: c(0x3B4758),
        warn: c(0xFFB020),
        good: c(0x24C26E),
        line: c(0x243044)
    )

    static let day = HUDPalette(
        background: c(0xF4F6F9),
        panel: c(0xE3E8EF),
        text: c(0x0B1220),
        dim: c(0x556173),
        accent: c(0x1463E0),
        onAccent: c(0xFFFFFF),
        route: c(0x1463E0),
        routeCasing: c(0xFFFFFF),
        routeDone: c(0xA6B1C2),
        warn: c(0xC46A00),
        good: c(0x0E9F5B),
        line: c(0xC7CFDB)
    )
}

/// Iconos de maniobra hechos con trazos, para que sean idénticos en el iPhone y en la moto.
enum HUDIcons {
    /// Dibuja la maniobra dentro de `rect`. El contexto debe tener el eje Y hacia abajo.
    /// `hole` es el color de fondo, para los huecos del icono.
    static func draw(_ kind: ManeuverKind, in rect: CGRect, color: CGColor, hole: CGColor, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 100, y: rect.height / 100)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(13)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch kind {
        case .depart, .straight:
            bent(ctx, start: CGPoint(x: 50, y: 92), bend: CGPoint(x: 50, y: 60), angle: 0, length: 24, head: 30, radius: 0)
        case .right:
            turn(ctx)
        case .left:
            mirror(ctx)
            turn(ctx)
        case .slightRight:
            slight(ctx)
        case .slightLeft:
            mirror(ctx)
            slight(ctx)
        case .sharpRight:
            sharp(ctx)
        case .sharpLeft:
            mirror(ctx)
            sharp(ctx)
        case .uTurn:
            uTurn(ctx)
        case .roundabout:
            roundabout(ctx)
        case .keepRight:
            fork(ctx, color: color)
        case .keepLeft:
            mirror(ctx)
            fork(ctx, color: color)
        case .arrive:
            pin(ctx, hole: hole)
        }
        ctx.restoreGState()
    }

    private static func mirror(_ ctx: CGContext) {
        ctx.translateBy(x: 100, y: 0)
        ctx.scaleBy(x: -1, y: 1)
    }

    private static func turn(_ ctx: CGContext) {
        bent(ctx, start: CGPoint(x: 30, y: 92), bend: CGPoint(x: 30, y: 42), angle: 90, length: 22, head: 30, radius: 13)
    }

    private static func slight(_ ctx: CGContext) {
        bent(ctx, start: CGPoint(x: 38, y: 92), bend: CGPoint(x: 38, y: 58), angle: 45, length: 18, head: 30, radius: 16)
    }

    private static func sharp(_ ctx: CGContext) {
        bent(ctx, start: CGPoint(x: 32, y: 92), bend: CGPoint(x: 32, y: 26), angle: 135, length: 18, head: 28, radius: 7)
    }

    private static func head(_ ctx: CGContext, tip: CGPoint, dir: CGPoint, size: CGFloat) {
        let normal = CGPoint(x: -dir.y, y: dir.x)
        let base = CGPoint(x: tip.x - dir.x * size, y: tip.y - dir.y * size)
        let half = size * 0.70
        ctx.beginPath()
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: base.x + normal.x * half, y: base.y + normal.y * half))
        ctx.addLine(to: CGPoint(x: base.x - normal.x * half, y: base.y - normal.y * half))
        ctx.closePath()
        ctx.fillPath()
    }

    /// Tallo vertical que dobla `angle` grados (horario desde arriba) y termina en punta.
    private static func bent(
        _ ctx: CGContext, start: CGPoint, bend: CGPoint, angle: CGFloat,
        length: CGFloat, head headSize: CGFloat, radius: CGFloat
    ) {
        let rad = angle * .pi / 180
        let dir = CGPoint(x: sin(rad), y: -cos(rad))
        let end = CGPoint(x: bend.x + dir.x * length, y: bend.y + dir.y * length)
        let tip = CGPoint(x: end.x + dir.x * headSize, y: end.y + dir.y * headSize)
        let inside = CGPoint(x: end.x + dir.x * headSize * 0.25, y: end.y + dir.y * headSize * 0.25)
        ctx.beginPath()
        ctx.move(to: start)
        if abs(angle) < 1 || radius <= 0 {
            ctx.addLine(to: bend)
            ctx.addLine(to: inside)
        } else {
            ctx.addArc(tangent1End: bend, tangent2End: end, radius: radius)
            ctx.addLine(to: inside)
        }
        ctx.strokePath()
        head(ctx, tip: tip, dir: dir, size: headSize)
    }

    private static func uTurn(_ ctx: CGContext) {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 68, y: 92))
        ctx.addLine(to: CGPoint(x: 68, y: 44))
        ctx.addCurve(to: CGPoint(x: 32, y: 44), control1: CGPoint(x: 68, y: 16), control2: CGPoint(x: 32, y: 16))
        ctx.addLine(to: CGPoint(x: 32, y: 62))
        ctx.strokePath()
        head(ctx, tip: CGPoint(x: 32, y: 92), dir: CGPoint(x: 0, y: 1), size: 28)
    }

    private static func roundabout(_ ctx: CGContext) {
        let center = CGPoint(x: 44, y: 46)
        let radius: CGFloat = 18
        ctx.setLineWidth(11)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: center.x, y: 94))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        ctx.strokePath()
        // Salida hacia arriba a la derecha.
        let len = (1.0 * 1.0 + 0.85 * 0.85).squareRoot()
        let dir = CGPoint(x: 1.0 / len, y: -0.85 / len)
        let from = CGPoint(x: center.x + dir.x * radius, y: center.y + dir.y * radius)
        let end = CGPoint(x: from.x + dir.x * 10, y: from.y + dir.y * 10)
        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: end)
        ctx.strokePath()
        head(ctx, tip: CGPoint(x: end.x + dir.x * 24, y: end.y + dir.y * 24), dir: dir, size: 26)
    }

    private static func fork(_ ctx: CGContext, color: CGColor) {
        // Ramal que no se toma, atenuado.
        ctx.saveGState()
        ctx.setAlpha(0.38)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 50, y: 62))
        ctx.addLine(to: CGPoint(x: 30, y: 26))
        ctx.strokePath()
        ctx.restoreGState()
        bent(ctx, start: CGPoint(x: 50, y: 92), bend: CGPoint(x: 50, y: 62), angle: 30, length: 20, head: 28, radius: 10)
    }

    private static func pin(_ ctx: CGContext, hole: CGColor) {
        let center = CGPoint(x: 50, y: 38)
        let radius: CGFloat = 26
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 50, y: 94))
        ctx.addLine(to: CGPoint(x: center.x - radius * 0.86, y: center.y + radius * 0.52))
        ctx.addLine(to: CGPoint(x: center.x + radius * 0.86, y: center.y + radius * 0.52))
        ctx.closePath()
        ctx.fillPath()
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.setFillColor(hole)
        ctx.fillEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
    }
}

/// Dibuja un fotograma completo para la pantalla de la moto.
final class HUDRenderer {
    private let width: CGFloat
    private let height: CGFloat
    /// Escala respecto al diseño base, pensado para 400 px de alto.
    private let k: CGFloat
    /// Píxeles por metro del minimapa. Se suaviza entre fotogramas.
    private var zoom: CGFloat = 0.6
    private var zoomReady = false

    init(width: Int, height: Int) {
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        k = CGFloat(height) / 400
    }

    /// El contexto debe tener el origen arriba a la izquierda y el eje Y hacia abajo.
    func draw(_ s: HUDSnapshot, now: Date, in ctx: CGContext) {
        let p = s.style == .day ? HUDPalette.day : HUDPalette.night
        ctx.setFillColor(p.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if s.arrived {
            zoomReady = false
            drawArrived(s, p, ctx)
        } else if s.navigating {
            drawGuidance(s, p, now, ctx)
        } else {
            zoomReady = false
            drawIdle(s, p, now, ctx)
        }
    }

    // MARK: - Navegación

    private func drawGuidance(_ s: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ ctx: CGContext) {
        let mapWidth = (width * 0.375).rounded()
        let leftWidth = width - mapWidth
        drawMiniMap(s, p, now, CGRect(x: leftWidth, y: 0, width: mapWidth, height: height), ctx)

        let pad = 24 * k
        let tile = s.rerouting ? p.warn : p.accent

        // Flecha de la maniobra.
        let box = CGRect(x: pad, y: 22 * k, width: 148 * k, height: 148 * k)
        fillRounded(box, radius: 32 * k, color: tile, ctx)
        HUDIcons.draw(s.kind, in: box.insetBy(dx: 17 * k, dy: 17 * k), color: p.onAccent, hole: tile, ctx: ctx)

        // Distancia hasta la maniobra.
        let parts = HUDFormat.distanceParts(s.distanceToManeuver)
        let numberX = box.maxX + 22 * k
        let number = measure(parts.value, size: 104 * k, bold: true, color: p.text)
        let baseline = 24 * k + number.ascent
        put(number, x: numberX, baseline: baseline, ctx)
        let unit = measure(parts.unit, size: 46 * k, bold: true, color: p.dim)
        put(unit, x: numberX + number.width + 10 * k, baseline: baseline, ctx)

        if let then = s.thenKind {
            let label = measure("Luego", size: 24 * k, bold: false, color: p.dim)
            let top = 132 * k
            put(label, x: numberX, baseline: top + 8 * k + label.ascent, ctx)
            HUDIcons.draw(
                then,
                in: CGRect(x: numberX + label.width + 10 * k, y: top, width: 42 * k, height: 42 * k),
                color: p.text, hole: p.background, ctx: ctx
            )
        }

        if s.simulated {
            let tag = measure("SIMULACIÓN", size: 17 * k, bold: true, color: p.warn)
            put(tag, x: leftWidth - pad - tag.width, baseline: 6 * k + tag.ascent, ctx)
        }

        // Instrucción (hasta dos líneas).
        let instruction = s.rerouting ? "Recalculando la ruta…" : s.instruction
        wrapped(
            instruction,
            sizes: [40, 36, 32, 28].map { $0 * k },
            color: s.rerouting ? p.warn : p.text,
            x: pad, top: 184 * k, width: leftWidth - pad * 2, maxLines: 2, ctx
        )

        // Barra inferior: llegada, tiempo y distancia restantes.
        let barTop = height - 92 * k
        ctx.setFillColor(p.line)
        ctx.fill(CGRect(x: pad, y: barTop, width: leftWidth - pad * 2, height: max(1, 2 * k)))
        let columnWidth = (leftWidth - pad * 2) / 3
        let clock = s.eta.map { HUDFormat.clock($0) }
        column(clock?.time ?? "--:--", "llegada " + (clock?.suffix ?? ""), x: pad, top: barTop + 10 * k, p, ctx)
        column(HUDFormat.durationCompact(s.remainingTime), "restante", x: pad + columnWidth, top: barTop + 10 * k, p, ctx)
        column(HUDFormat.distance(s.remainingDistance), "distancia", x: pad + columnWidth * 2, top: barTop + 10 * k, p, ctx)

        let track = CGRect(x: pad, y: height - 10 * k, width: leftWidth - pad * 2, height: 5 * k)
        fillRounded(track, radius: 2.5 * k, color: p.line, ctx)
        let fraction = CGFloat(max(0, min(1, s.fraction)))
        if fraction > 0.01 {
            fillRounded(
                CGRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height),
                radius: 2.5 * k, color: p.accent, ctx
            )
        }
    }

    private func column(_ value: String, _ label: String, x: CGFloat, top: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        let v = measure(value, size: 36 * k, bold: true, color: p.text)
        put(v, x: x, baseline: top + v.ascent, ctx)
        let l = measure(label, size: 18 * k, bold: false, color: p.dim)
        put(l, x: x, baseline: top + 44 * k + l.ascent, ctx)
    }

    private func drawMiniMap(_ s: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(p.panel)
        ctx.fill(rect)

        let anchor = CGPoint(x: rect.midX, y: rect.maxY - 80 * k)

        if let shape = s.shape, shape.points.count >= 2 {
            // Avanzar la posición entre fijos del GPS para que el movimiento sea continuo.
            let dt = max(0, min(1.5, now.timeIntervalSinceReferenceDate - s.fixTime))
            let progress = max(0, min(shape.length, s.progress + s.speed * dt))
            let position = shape.point(at: progress)
            let bearing = shape.bearing(at: progress, span: 18)

            // Zoom: que se vea hasta un poco más allá de la próxima maniobra.
            let toManeuver = max(0, (s.maneuverAt ?? shape.length) - progress)
            let ahead = min(max(toManeuver * 1.35, 150), 650)
            let usable = anchor.y - rect.minY - 30 * k
            let target = usable / CGFloat(ahead)
            if zoomReady {
                zoom += (target - zoom) * 0.12
            } else {
                zoom = target
                zoomReady = true
            }
            let scale = zoom

            let cosB = CGFloat(cos(bearing))
            let sinB = CGFloat(sin(bearing))
            func project(_ q: CGPoint) -> CGPoint {
                let dx = q.x - position.x
                let dy = q.y - position.y
                let forward = dx * sinB + dy * cosB
                let right = dx * cosB - dy * sinB
                return CGPoint(x: anchor.x + right * scale, y: anchor.y - forward * scale)
            }

            let visible = Double(rect.height / scale) + 80
            let from = max(0, progress - 130)
            let to = min(shape.length, progress + visible)

            func trace(_ a: Double, _ b: Double) -> CGPath {
                let line = CGMutablePath()
                line.move(to: project(shape.point(at: a)))
                let first = shape.segmentIndex(at: a) + 1
                let last = shape.segmentIndex(at: b)
                if first <= last {
                    for i in first...last {
                        line.addLine(to: project(shape.points[i]))
                    }
                }
                line.addLine(to: project(shape.point(at: b)))
                return line
            }

            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let whole = trace(from, to)
            ctx.addPath(whole)
            ctx.setStrokeColor(p.routeCasing)
            ctx.setLineWidth(22 * k)
            ctx.strokePath()
            ctx.addPath(whole)
            ctx.setStrokeColor(p.route)
            ctx.setLineWidth(14 * k)
            ctx.strokePath()
            if progress - from > 1 {
                ctx.addPath(trace(from, progress))
                ctx.setStrokeColor(p.routeDone)
                ctx.setLineWidth(14 * k)
                ctx.strokePath()
            }

            // Punto de la próxima maniobra.
            if let at = s.maneuverAt, at > progress + 4, at <= to {
                let m = project(shape.point(at: at))
                ctx.setFillColor(p.accent)
                ctx.fillEllipse(in: CGRect(x: m.x - 13 * k, y: m.y - 13 * k, width: 26 * k, height: 26 * k))
                ctx.setFillColor(p.onAccent)
                ctx.fillEllipse(in: CGRect(x: m.x - 8 * k, y: m.y - 8 * k, width: 16 * k, height: 16 * k))
            }

            // Indicador del norte.
            let compass = CGPoint(x: rect.maxX - 36 * k, y: rect.minY + 36 * k)
            ctx.setFillColor(p.background)
            ctx.fillEllipse(in: CGRect(x: compass.x - 22 * k, y: compass.y - 22 * k, width: 44 * k, height: 44 * k))
            let north = CGPoint(x: -sinB, y: -cosB)
            let side = CGPoint(x: -north.y, y: north.x)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: compass.x + north.x * 17 * k, y: compass.y + north.y * 17 * k))
            ctx.addLine(to: CGPoint(x: compass.x + side.x * 7 * k, y: compass.y + side.y * 7 * k))
            ctx.addLine(to: CGPoint(x: compass.x - side.x * 7 * k, y: compass.y - side.y * 7 * k))
            ctx.closePath()
            ctx.setFillColor(p.warn)
            ctx.fillPath()
            ctx.setFillColor(p.dim)
            ctx.fillEllipse(in: CGRect(x: compass.x - 4 * k, y: compass.y - 4 * k, width: 8 * k, height: 8 * k))
        }

        cursor(at: anchor, size: 1.0, p, ctx)
        ctx.restoreGState()

        ctx.setFillColor(p.line)
        ctx.fill(CGRect(x: rect.minX, y: 0, width: max(1, 2 * k), height: height))
    }

    /// Marca de posición: una punta de flecha que mira hacia arriba.
    private func cursor(at c: CGPoint, size: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        let u = k * size
        ctx.saveGState()
        ctx.setFillColor(p.accent)
        ctx.setAlpha(0.20)
        ctx.fillEllipse(in: CGRect(x: c.x - 34 * u, y: c.y - 34 * u, width: 68 * u, height: 68 * u))
        ctx.restoreGState()

        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: c.x, y: c.y - 24 * u))
        shape.addLine(to: CGPoint(x: c.x + 18 * u, y: c.y + 18 * u))
        shape.addLine(to: CGPoint(x: c.x, y: c.y + 8 * u))
        shape.addLine(to: CGPoint(x: c.x - 18 * u, y: c.y + 18 * u))
        shape.closeSubpath()
        ctx.setLineJoin(.round)
        ctx.addPath(shape)
        ctx.setStrokeColor(p.onAccent)
        ctx.setLineWidth(7 * u)
        ctx.strokePath()
        ctx.addPath(shape)
        ctx.setFillColor(p.accent)
        ctx.fillPath()
    }

    // MARK: - Sin destino y llegada

    private func drawIdle(_ s: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ ctx: CGContext) {
        let pad = 36 * k
        let brand = measure("CFMoto Link", size: 26 * k, bold: true, color: p.accent)
        put(brand, x: pad, baseline: 30 * k + brand.ascent, ctx)

        let clock = HUDFormat.clock(now)
        let time = measure(clock.time, size: 138 * k, bold: true, color: p.text)
        let baseline = 78 * k + time.ascent
        put(time, x: pad, baseline: baseline, ctx)
        let suffix = measure(clock.suffix, size: 38 * k, bold: false, color: p.dim)
        put(suffix, x: pad + time.width + 14 * k, baseline: baseline, ctx)

        let hint = measure("Elige un destino en el iPhone", size: 31 * k, bold: false, color: p.dim)
        put(hint, x: pad, baseline: 262 * k + hint.ascent, ctx)

        ctx.setFillColor(s.gpsOk ? p.good : p.warn)
        ctx.fillEllipse(in: CGRect(x: pad, y: 336 * k, width: 16 * k, height: 16 * k))
        let gps = measure(s.gpsOk ? "GPS listo" : "Buscando señal GPS…", size: 24 * k, bold: false, color: p.dim)
        put(gps, x: pad + 28 * k, baseline: 330 * k + gps.ascent, ctx)

        // Adorno: anillos con la marca de posición.
        let center = CGPoint(x: width - 138 * k, y: height / 2)
        ctx.setStrokeColor(p.line)
        ctx.setLineWidth(3 * k)
        for radius in [112 * k, 76 * k] {
            ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        cursor(at: center, size: 1.5, p, ctx)
    }

    private func drawArrived(_ s: HUDSnapshot, _ p: HUDPalette, _ ctx: CGContext) {
        let pad = 36 * k
        let box = CGRect(x: pad, y: 100 * k, width: 200 * k, height: 200 * k)
        fillRounded(box, radius: 44 * k, color: p.good, ctx)
        HUDIcons.draw(.arrive, in: box.insetBy(dx: 30 * k, dy: 30 * k), color: p.onAccent, hole: p.good, ctx: ctx)

        let x = box.maxX + 34 * k
        let title = measure("Has llegado", size: 84 * k, bold: true, color: p.text)
        put(title, x: x, baseline: 108 * k + title.ascent, ctx)
        wrapped(
            s.destinationName,
            sizes: [38, 32, 28].map { $0 * k },
            color: p.dim, x: x, top: 214 * k, width: width - x - pad, maxLines: 2, ctx
        )
    }

    // MARK: - Utilidades de dibujo

    private func fillRounded(_ rect: CGRect, radius: CGFloat, color: CGColor, _ ctx: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    private struct Measured {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    private func font(_ size: CGFloat, bold: Bool) -> CTFont {
        if let f = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) {
            return f
        }
        return CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    }

    private func attributes(size: CGFloat, bold: Bool, color: CGColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size, bold: bold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
    }

    private func measured(_ line: CTLine) -> Measured {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return Measured(line: line, width: width, ascent: ascent, descent: descent)
    }

    private func measure(_ text: String, size: CGFloat, bold: Bool, color: CGColor) -> Measured {
        let attributed = NSAttributedString(string: text, attributes: attributes(size: size, bold: bold, color: color))
        return measured(CTLineCreateWithAttributedString(attributed))
    }

    private func put(_ m: Measured, x: CGFloat, baseline: CGFloat, _ ctx: CGContext) {
        // El contexto tiene el eje Y hacia abajo: se invierte solo el texto.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(m.line, ctx)
    }

    /// Texto en varias líneas. Prueba tamaños de mayor a menor y recorta con "…" si no cabe.
    private func wrapped(
        _ text: String, sizes: [CGFloat], color: CGColor,
        x: CGFloat, top: CGFloat, width: CGFloat, maxLines: Int, _ ctx: CGContext
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, width > 10 else { return }
        for (index, size) in sizes.enumerated() {
            let attrs = attributes(size: size, bold: true, color: color)
            let attributed = NSAttributedString(string: clean, attributes: attrs)
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let total = attributed.length
            var start = 0
            var lastStart = 0
            var lines: [CTLine] = []
            while start < total && lines.count < maxLines {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                if count <= 0 { break }
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
                lastStart = start
                start += count
            }
            let fits = start >= total
            let isLast = index == sizes.count - 1
            if !fits && !isLast { continue }
            if !fits, !lines.isEmpty {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: lastStart, length: total - lastStart))
                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
                if let cut = CTLineCreateTruncatedLine(rest, Double(width), .end, ellipsis) {
                    lines[lines.count - 1] = cut
                }
            }
            var y = top
            for line in lines {
                let m = measured(line)
                put(m, x: x, baseline: y + m.ascent, ctx)
                y += m.ascent + m.descent + size * 0.10
            }
            return
        }
    }
}
