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

    // 0.6.3: sistema visual de la referencia (tarjetas de vidrio con borde luminoso, mosaicos
    // con degradado y ruta con resplandor). Lo comparten todas las tarjetas del panel.
    /// Tema oscuro (para las imágenes guardadas de las tarjetas).
    let dark: Bool
    /// Texto terciario (etiquetas pequeñas).
    let faint: CGColor
    /// Vidrio de las tarjetas: arriba y abajo.
    let cardTop: CGColor
    let cardBottom: CGColor
    /// Borde luminoso: más claro arriba.
    let edgeTop: CGColor
    let edgeBottom: CGColor
    /// Halo exterior muy suave (solo de noche).
    let halo: CGColor
    let shadow: CGColor
    /// Zonas del panel (degradado de fondo).
    let panelTop: CGColor
    let panelBottom: CGColor
    let divider: CGColor
    /// Mosaico de la maniobra (degradado azul).
    let tileTop: CGColor
    let tileBottom: CGColor
    /// Ruta: resplandor alrededor y brillo en el centro.
    let routeGlow: CGColor
    let routeLight: CGColor
    /// Marca del destino.
    let pin: CGColor

    private static func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let night = HUDPalette(
        background: c(0x04080F),
        panel: c(0x0A1322),
        text: c(0xFFFFFF),
        dim: c(0xA7B4C9),
        accent: c(0x2F86FF),
        onAccent: c(0xFFFFFF),
        route: c(0x2B8CFF),
        routeCasing: c(0x0A3A99),
        routeDone: c(0x3B4758),
        warn: c(0xFFB020),
        good: c(0x22C46E),
        line: c(0x22324A),
        dark: true,
        faint: c(0x7D8BA2),
        cardTop: c(0x182740, 0.93),
        cardBottom: c(0x0A1222, 0.94),
        edgeTop: c(0x7DB8FF, 0.8),
        edgeBottom: c(0x3567C4, 0.36),
        halo: c(0x3D8BFF, 0.17),
        shadow: c(0x000000, 0.55),
        panelTop: c(0x111C30),
        panelBottom: c(0x080F1C),
        divider: c(0xFFFFFF, 0.14),
        tileTop: c(0x52A3FF),
        tileBottom: c(0x1A58DC),
        routeGlow: c(0x2B8CFF, 0.26),
        routeLight: c(0x8CC4FF),
        pin: c(0xFF3B4A)
    )

    static let day = HUDPalette(
        background: c(0xEDF1F6),
        panel: c(0xE2E8F1),
        text: c(0x0A1220),
        dim: c(0x4A5667),
        accent: c(0x1463E0),
        onAccent: c(0xFFFFFF),
        route: c(0x1A6FEA),
        routeCasing: c(0xFFFFFF),
        routeDone: c(0xA6B1C2),
        warn: c(0xC46A00),
        good: c(0x0E9F5B),
        line: c(0xC7CFDB),
        dark: false,
        faint: c(0x667285),
        cardTop: c(0xFFFFFF, 0.95),
        cardBottom: c(0xEDF2F9, 0.95),
        edgeTop: c(0xFFFFFF, 0.95),
        edgeBottom: c(0x8FA6CC, 0.55),
        halo: c(0x1463E0, 0),
        shadow: c(0x0A1A33, 0.28),
        panelTop: c(0xF7F9FC),
        panelBottom: c(0xE3E9F2),
        divider: c(0x0A1220, 0.12),
        tileTop: c(0x3D8BFF),
        tileBottom: c(0x1250CC),
        routeGlow: c(0x1A6FEA, 0.2),
        routeLight: c(0x7DB6FF),
        pin: c(0xE5243B)
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
    let width: CGFloat
    let height: CGFloat
    /// Escala respecto al diseño base, pensado para 400 px de alto.
    let k: CGFloat
    /// Píxeles por metro del minimapa. Se suaviza entre fotogramas.
    var zoom: CGFloat = 0.6
    var zoomReady = false

    /// Parte baja de la imagen que la moto tapa con sus propios indicadores (velocidad, marcha).
    /// Ahí no se dibuja nada importante. 0 = usar toda la altura.
    static var reservedBottom: CGFloat = 0
    /// Desplazamiento de la brújula del mapa cuando hay etiquetas en esa esquina.
    var compassDrop: CGFloat = 0
    /// Sitio de la hora actual si cae dentro de la zona que se está dibujando (esa zona lo deja
    /// libre). Solo en los diseños por zonas; sobre el mapa la hora es una tarjeta más.
    var statusReserve: CGRect?
    /// Fondo de la pantalla de música ya dibujado (los degradados cambian solo con la canción):
    /// se reutiliza en cada fotograma para gastar menos CPU.
    /// 0.6.4: los últimos fondos (el de la canción de ahora y, durante el cambio, el de la
    /// anterior: el cambio es un fundido entre los dos, sin volver a dibujarlos).
    var stageBackgrounds: [(key: String, image: CGImage)] = []
    /// Las pruebas lo apagan para comparar con el dibujo directo.
    static var cacheStageBackground = true
    /// 0.6.3: fondos de las tarjetas de vidrio ya dibujados (sombra, degradado y borde), por
    /// tamaño y tema. Solo cambian si cambia el tamaño, así que se reutilizan en cada fotograma.
    var cardImages: [String: CGImage] = [:]
    static var cacheCards = true
    /// 0.6.4: «luz» de las últimas portadas (sus colores reducidos a 4×4 y ampliados), para el
    /// fondo de la música. Se calcula una vez por portada y tema.
    var ambientCache: [(art: CGImage, night: Bool, image: CGImage, signature: String)] = []
    /// 0.6.4: la luz de la portada ya ampliada al tamaño del reproductor.
    var ambientScaledCache: [(art: CGImage, night: Bool, w: Int, h: Int, image: CGImage)] = []
    /// 0.6.4: sombras difuminadas de la portada ya dibujadas, por tamaño y tema.
    var shadowImages: [String: CGImage] = [:]
    /// Solo para las pruebas (0.6.4): cada botón del reproductor que se dibuja (anterior,
    /// reproducir, pausa, siguiente), con su sitio, su zona o tarjeta y su transparencia.
    struct ControlMark {
        let kind: String
        let rect: CGRect
        let box: CGRect
        let alpha: CGFloat
    }
    var controlMarks: [ControlMark] = []
    /// Solo para las pruebas: dibuja todo menos los botones (para medir su contraste con el fondo).
    static var hideControls = false
    /// Solo para las pruebas (0.6.3): cada texto que se dibuja, con su caja y el recorte vigente,
    /// para comprobar que nada se corta, se monta ni tapa la hora. En la app está apagado.
    struct TextMark {
        let text: String
        let rect: CGRect
        /// Zona o tarjeta en la que va (o el recorte vigente).
        let box: CGRect
        let truncated: Bool
    }
    static var recordText = false
    /// Solo para las pruebas: dibuja todo menos los textos (para medir el contraste con el fondo).
    static var hideText = false
    var textMarks: [TextMark] = []
    /// Zona o tarjeta que se está dibujando (solo lo usan las pruebas).
    var textBox: CGRect?
    /// El mapa simple dibuja su propia brújula salvo que el panel la ponga en otro sitio.
    var miniCompass = true
    /// Rumbo de la ruta en el último dibujo simple (radianes), para la brújula del panel.
    var lastBearing: Double = 0
    let fullHeight: CGFloat

    init(width: Int, height: Int) {
        self.width = CGFloat(width)
        fullHeight = CGFloat(height)
        let usable = (CGFloat(height) * (1 - max(0, min(0.4, HUDRenderer.reservedBottom)))).rounded()
        self.height = usable
        k = usable / 400
    }

    /// El contexto debe tener el origen arriba a la izquierda y el eje Y hacia abajo.
    func draw(_ s: HUDSnapshot, now: Date, in ctx: CGContext) {
        let p = s.style == .day ? HUDPalette.day : HUDPalette.night
        ctx.setFillColor(p.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: fullHeight))
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

    func drawGuidance(_ s: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ ctx: CGContext) {
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

    func column(_ value: String, _ label: String, x: CGFloat, top: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        let v = measure(value, size: 36 * k, bold: true, color: p.text)
        put(v, x: x, baseline: top + v.ascent, ctx)
        let l = measure(label, size: 18 * k, bold: false, color: p.dim)
        put(l, x: x, baseline: top + 44 * k + l.ascent, ctx)
    }

    func drawMiniMap(
        _ s: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ rect: CGRect, _ ctx: CGContext,
        anchor fixed: CGPoint? = nil, unit: CGFloat? = nil, divider: Bool = true
    ) {
        let u = unit ?? k
        ctx.saveGState()
        ctx.clip(to: rect)
        // 0.6.3: fondo azul oscuro con degradado, como el mapa de la referencia (sin calles
        // inventadas: este es el dibujo simple de la ruta, sin mapa).
        fillVertical(rect, p.panelTop, p.panelBottom, ctx)

        let anchor = fixed ?? CGPoint(x: rect.midX, y: rect.maxY - 80 * u)

        if let shape = s.shape, shape.points.count >= 2 {
            // Avanzar la posición entre fijos del GPS para que el movimiento sea continuo.
            let dt = max(0, min(1.5, now.timeIntervalSinceReferenceDate - s.fixTime))
            let progress = max(0, min(shape.length, s.progress + s.speed * dt))
            let position = shape.point(at: progress)
            let bearing = shape.bearing(at: progress, span: 18)

            // Zoom: que se vea hasta un poco más allá de la próxima maniobra.
            let toManeuver = max(0, (s.maneuverAt ?? shape.length) - progress)
            let ahead = min(max(toManeuver * 1.35, 150), 650)
            let usable = anchor.y - rect.minY - 30 * u
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
            // Lo recorrido, gris; lo que falta, con resplandor, borde, línea y brillo central (la
            // misma ruta que sobre el mapa de calles).
            if progress - from > 1 {
                let done = trace(from, progress)
                ctx.addPath(done)
                ctx.setStrokeColor(p.routeDone)
                ctx.setLineWidth(14 * u)
                ctx.strokePath()
            }
            let rest = trace(progress, to)
            ctx.addPath(rest)
            ctx.setStrokeColor(p.routeGlow)
            ctx.setLineWidth(32 * u)
            ctx.strokePath()
            ctx.addPath(rest)
            ctx.setStrokeColor(p.routeCasing)
            ctx.setLineWidth(21 * u)
            ctx.strokePath()
            ctx.addPath(rest)
            ctx.setStrokeColor(p.route)
            ctx.setLineWidth(14 * u)
            ctx.strokePath()
            ctx.addPath(rest)
            ctx.setStrokeColor(p.routeLight)
            ctx.setLineWidth(4 * u)
            ctx.strokePath()

            // Punto de la próxima maniobra.
            if let at = s.maneuverAt, at > progress + 4, at <= to {
                let m = project(shape.point(at: at))
                ctx.setFillColor(p.accent)
                ctx.fillEllipse(in: CGRect(x: m.x - 13 * u, y: m.y - 13 * u, width: 26 * u, height: 26 * u))
                ctx.setFillColor(p.onAccent)
                ctx.fillEllipse(in: CGRect(x: m.x - 8 * u, y: m.y - 8 * u, width: 16 * u, height: 16 * u))
            }

            // Indicador del norte.
            if miniCompass {
                // La misma brújula de vidrio que sobre el mapa de calles.
                let box = CGRect(x: rect.maxX - 58 * u, y: rect.minY + 14 * u + compassDrop, width: 44 * u, height: 44 * u)
                drawCompass(in: box, angle: CGFloat(-bearing), p, ctx)
            }
            lastBearing = bearing
        }

        cursor(at: anchor, size: u / k, p, ctx)
        ctx.restoreGState()

        if divider {
            ctx.setFillColor(p.line)
            ctx.fill(CGRect(x: rect.minX, y: 0, width: max(1, 2 * u), height: height))
        }
    }

    /// Marca de posición: una punta de flecha que mira hacia arriba.
    func cursor(at c: CGPoint, size: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        positionMark(at: c, angle: 0, u: k * size * 1.1, p, ctx)
    }

    /// Marca de posición (0.6.3, como en la referencia): halo azul, disco de vidrio con borde
    /// claro y la flecha con degradado azul y borde blanco. Sin rumbo, un punto azul.
    /// `angle`: radianes desde arriba, en el sentido de las agujas del reloj.
    func positionMark(at c: CGPoint, angle: CGFloat?, u: CGFloat, _ p: HUDPalette, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(p.accent.copy(alpha: p.dark ? 0.2 : 0.16) ?? p.accent)
        ctx.fillEllipse(in: CGRect(x: c.x - 31 * u, y: c.y - 31 * u, width: 62 * u, height: 62 * u))
        let disk = CGRect(x: c.x - 20 * u, y: c.y - 20 * u, width: 40 * u, height: 40 * u)
        ctx.setShadow(offset: .zero, blur: 6 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: p.dark ? 0.6 : 0.3))
        ctx.setFillColor(p.dark ? CGColor(srgbRed: 0.05, green: 0.1, blue: 0.19, alpha: 0.95) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.97))
        ctx.fillEllipse(in: disk)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(p.dark ? CGColor(srgbRed: 0.62, green: 0.8, blue: 1, alpha: 0.9) : p.accent)
        ctx.setLineWidth(2 * u)
        ctx.strokeEllipse(in: disk.insetBy(dx: 1 * u, dy: 1 * u))
        guard let angle = angle else {
            ctx.setFillColor(p.onAccent)
            ctx.fillEllipse(in: CGRect(x: c.x - 9 * u, y: c.y - 9 * u, width: 18 * u, height: 18 * u))
            ctx.setFillColor(p.accent)
            ctx.fillEllipse(in: CGRect(x: c.x - 6.5 * u, y: c.y - 6.5 * u, width: 13 * u, height: 13 * u))
            ctx.restoreGState()
            return
        }
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 0, y: -15.5 * u))
        arrow.addLine(to: CGPoint(x: 12 * u, y: 12 * u))
        arrow.addLine(to: CGPoint(x: 0, y: 5.5 * u))
        arrow.addLine(to: CGPoint(x: -12 * u, y: 12 * u))
        arrow.closeSubpath()
        ctx.saveGState()
        ctx.addPath(arrow)
        ctx.clip()
        fillVertical(CGRect(x: -12.5 * u, y: -15.5 * u, width: 25 * u, height: 27.5 * u), p.tileTop, p.tileBottom, ctx)
        ctx.restoreGState()
        ctx.addPath(arrow)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(p.onAccent)
        ctx.setLineWidth(1.8 * u)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Sin destino y llegada

    func drawIdle(_ s: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ ctx: CGContext) {
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

    func drawArrived(_ s: HUDSnapshot, _ p: HUDPalette, _ ctx: CGContext) {
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

    func fillRounded(_ rect: CGRect, radius: CGFloat, color: CGColor, _ ctx: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    struct Measured {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        /// Texto de la línea y si termina en "…" (para las pruebas).
        var text: String = ""
        var truncated = false
    }

    func font(_ size: CGFloat, bold: Bool) -> CTFont {
        if let f = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) {
            return f
        }
        return CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    }

    func attributes(size: CGFloat, bold: Bool, color: CGColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size, bold: bold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
    }

    func measured(_ line: CTLine) -> Measured {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return Measured(line: line, width: width, ascent: ascent, descent: descent)
    }

    func measure(_ text: String, size: CGFloat, bold: Bool, color: CGColor) -> Measured {
        let attributed = NSAttributedString(string: text, attributes: attributes(size: size, bold: bold, color: color))
        var m = measured(CTLineCreateWithAttributedString(attributed))
        m.text = text
        return m
    }

    /// Línea `range` de un texto partido en varias (con "…" si es la última y no cabía).
    func measured(_ line: CTLine, in text: String, range: CFRange, truncated: Bool) -> Measured {
        var m = measured(line)
        let ns = text as NSString
        let loc = max(0, min(ns.length, range.location))
        m.text = ns.substring(with: NSRange(location: loc, length: max(0, min(ns.length - loc, range.length))))
        m.truncated = truncated
        return m
    }

    func put(_ m: Measured, x: CGFloat, baseline: CGFloat, _ ctx: CGContext) {
        if HUDRenderer.recordText {
            textMarks.append(TextMark(text: m.text, rect: CGRect(x: x, y: baseline - m.ascent, width: m.width, height: m.ascent + m.descent),
                                      box: textBox ?? ctx.boundingBoxOfClipPath, truncated: m.truncated))
        }
        if HUDRenderer.hideText { return }
        // El contexto tiene el eje Y hacia abajo: se invierte solo el texto.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(m.line, ctx)
    }

    /// Texto en varias líneas. Prueba tamaños de mayor a menor y recorta con "…" si no cabe.
    func wrapped(
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
            var ranges: [CFRange] = []
            while start < total && lines.count < maxLines {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                if count <= 0 { break }
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
                ranges.append(CFRange(location: start, length: count))
                lastStart = start
                start += count
            }
            let fits = start >= total
            let isLast = index == sizes.count - 1
            if !fits && !isLast { continue }
            var cutLast = false
            if !fits, !lines.isEmpty {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: lastStart, length: total - lastStart))
                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
                if let cut = CTLineCreateTruncatedLine(rest, Double(width), .end, ellipsis) {
                    lines[lines.count - 1] = cut
                    ranges[ranges.count - 1] = CFRange(location: lastStart, length: total - lastStart)
                    cutLast = true
                }
            }
            var y = top
            for (i, line) in lines.enumerated() {
                let m = measured(line, in: clean, range: ranges[i], truncated: cutLast && i == lines.count - 1)
                put(m, x: x, baseline: y + m.ascent, ctx)
                y += m.ascent + m.descent + size * 0.10
            }
            return
        }
    }
}
