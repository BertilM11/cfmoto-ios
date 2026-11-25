// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Composición del panel para la moto: una sola imagen con todos los módulos activos.
// Igual que el resto del dibujo, usa solo CoreGraphics y CoreText (CPU).
import Foundation
import CoreGraphics
import CoreText

extension HUDRenderer {
    func alpha(_ c: CGColor, _ a: CGFloat) -> CGColor { c.copy(alpha: a) ?? c }

    /// Dibuja el panel completo en toda la imagen (o en la parte que el usuario deje libre).
    func drawDashboard(_ s: DashSnapshot, now: Date, in ctx: CGContext) {
        let p = s.night ? HUDPalette.night : HUDPalette.day
        ctx.setFillColor(p.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: fullHeight))

        var tags: [String] = []
        if s.demo { tags.append("DEMO") }
        if s.nav.navigating && s.nav.simulated { tags.append("SIMULACIÓN") }
        if s.nav.navigating && !s.nav.simulated && !s.nav.gpsOk { tags.append("SIN SEÑAL GPS") }
        // 0.6.3: con el iPhone bloqueado (mapa guardado en uso), aviso cuando queda poco mapa.
        if let tag = s.mapCoverage.tftTag(storedMapInUse: s.map.map { !$0.live } ?? false) { tags.append(tag) }

        statusReserve = nil
        if s.layout.template == .overlay {
            let area = CGRect(x: 0, y: 0, width: width, height: height)
            let streets = drawOverlay(s, p, now, area, ctx)
            if s.mapSettings.streets && !streets && !s.demo { tags.append("MAPA SIMPLE") }
            drawTags(tags, p, top: area.minY + 12 * k, ctx)
            return
        }

        let gap = (6 * k).rounded()
        var area = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: gap, dy: gap)
        // La hora actual: el mismo sitio que en los modos con mapa (arriba a la derecha).
        let clock = DashLayoutEngine.statusClock(in: CGRect(x: 0, y: 0, width: width, height: height), k: k)
        // Si el diseño no muestra la ruta y hay una en curso, el próximo giro va en una franja.
        let strip = !s.layout.showsRoute && s.nav.navigating && !s.nav.arrived
        if strip { area.size.height -= 62 * k + gap }
        let frames = DashLayoutEngine.frames(s.layout, in: area, gap: gap)
        if frames.isEmpty {
            let m = measure("Panel vacío: activa un módulo en Mi pantalla", size: 22 * k, bold: true, color: p.dim)
            put(m, x: area.midX - m.width / 2, baseline: area.midY, ctx)
        }
        for f in frames {
            ctx.saveGState()
            textBox = f.rect
            // La zona que queda debajo de la hora la deja libre (la brújula baja, el texto empieza
            // más abajo y la cabecera de la música se acorta).
            statusReserve = f.rect.intersects(clock) ? clock : nil
            compassDrop = statusReserve.map { max(0, $0.maxY - f.rect.minY - 4 * k) } ?? 0
            let radius = 14 * k
            ctx.addPath(CGPath(roundedRect: f.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
            // 0.6.3: cada zona es un panel de vidrio (degradado oscuro y borde luminoso).
            fillVertical(f.rect, p.panelTop, p.panelBottom, ctx)
            switch f.module {
            case .nav: dashNav(s, p, now, f.rect, ctx)
            case .turn: dashTurn(s.nav, p, belowStatus(f.rect), ctx)
            case .map: dashMap(s, p, now, f.rect, ctx)
            case .trip: dashTrip(s.nav, p, now, belowStatus(f.rect), ctx)
            case .music: dashPlayer(s, p, now, f.rect, ctx, card: nil)
            case .notices: dashNotices(s, p, now, belowStatus(f.rect), ctx)
            case .clock: dashClock(p, now, belowStatus(f.rect), ctx)
            }
            ctx.restoreGState()
            if f.module == .music {
                let c = musicColors(s)
                glassEdge(f.rect, radius: radius, top: musicEdge(c, s.night).top, bottom: musicEdge(c, s.night).bottom, width: 1.25 * k, ctx)
            } else {
                glassEdge(f.rect, radius: radius, top: p.edgeTop, bottom: p.edgeBottom, width: 1.25 * k, ctx)
            }
        }
        compassDrop = 0
        statusReserve = nil
        textBox = nil
        if strip {
            let r = CGRect(x: area.minX, y: area.maxY + gap, width: area.width, height: 62 * k)
            textBox = r
            dashTurnStrip(s.nav, p, r, ctx)
            textBox = nil
        }

        dashStatusClock(p, now, clock, ctx)
        // Etiquetas de estado (DEMO, SIMULACIÓN…). 0.6.3: dentro de la zona del mapa, arriba a la
        // derecha, para no caer sobre la música ni los avisos; sin mapa, junto a la hora.
        var right = clock.minX - 8 * k
        var top = area.minY + 6 * k
        if !tags.isEmpty, let zone = frames.first(where: { $0.module == .nav || $0.module == .map }) {
            let r = zone.rect
            right = r.maxX - 9 * k
            if clock.intersects(CGRect(x: r.minX, y: r.minY + 9 * k, width: r.width, height: 22 * k)) { right = min(right, clock.minX - 8 * k) }
            let total = tags.reduce(CGFloat(0)) { $0 + measure($1, size: 13 * k, bold: true, color: p.background).width + 20 * k }
            var band = CGRect(x: right - total, y: r.minY + 9 * k, width: total, height: 22 * k)
            // Debajo de lo que haya en esa esquina (tarjeta, barra del viaje o brújula).
            var obstacles: [CGRect] = []
            let reserve: CGRect? = r.intersects(clock) ? clock : nil
            if zone.module == .nav {
                let L = NavZoneLayout.make(r, s.layout.overlay, k: k, reserve: reserve, trip: s.nav.navigating && !s.nav.arrived)
                obstacles = [L.card, L.trip, L.compass]
            } else {
                let drop = reserve.map { max(0, $0.maxY - r.minY - 4 * k) } ?? 0
                obstacles = [CGRect(x: r.maxX - 50 * k, y: r.minY + 10 * k + drop, width: 40 * k, height: 40 * k)]
            }
            for _ in 0..<3 {
                for o in obstacles where !o.isEmpty && o.intersects(band) { band.origin.y = o.maxY + 6 * k }
            }
            top = band.minY
        }
        for tag in tags {
            let m = measure(tag, size: 13 * k, bold: true, color: HUDRenderer.tagInk)
            let pill = CGRect(x: right - m.width - 14 * k, y: top, width: m.width + 14 * k, height: 22 * k)
            tagPill(pill, ctx)
            textBox = pill
            put(m, x: pill.minX + 7 * k, baseline: pill.midY + (m.ascent - m.descent) / 2, ctx)
            textBox = nil
            right = pill.minX - 6 * k
        }
    }

    /// Etiquetas de estado (DEMO, SIMULACIÓN…) centradas arriba.
    func drawTags(_ tags: [String], _ p: HUDPalette, top: CGFloat, _ ctx: CGContext) {
        guard !tags.isEmpty else { return }
        let ms = tags.map { measure($0, size: 13 * k, bold: true, color: HUDRenderer.tagInk) }
        let total = ms.reduce(0) { $0 + $1.width + 14 * k } + CGFloat(ms.count - 1) * 6 * k
        var x = width / 2 - total / 2
        for m in ms {
            let pill = CGRect(x: x, y: top, width: m.width + 14 * k, height: 22 * k)
            tagPill(pill, ctx)
            textBox = pill
            put(m, x: pill.minX + 7 * k, baseline: pill.midY + (m.ascent - m.descent) / 2, ctx)
            textBox = nil
            x = pill.maxX + 6 * k
        }
    }

    // MARK: - Sistema visual (0.6.3, según la referencia premium)
    //
    // Todas las tarjetas usan las mismas piezas: vidrio con degradado (oscuro de noche, claro de
    // día), borde luminoso más claro arriba, sombra suave y, de noche, un halo azul muy tenue.
    // Los iconos van en mosaicos con degradado y brillo. Todo con CoreGraphics (CPU), y los
    // fondos de las tarjetas se guardan ya dibujados para no repetir el trabajo en cada
    // fotograma.

    static let tagInk = CGColor(srgbRed: 0.1, green: 0.07, blue: 0, alpha: 1)

    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    static func white(_ a: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

    /// Degradados de los mosaicos de icono (arriba, abajo).
    enum Tile {
        case blue, warn, good, gray, amber, violet
    }

    func tileColors(_ t: Tile, _ p: HUDPalette) -> (CGColor, CGColor) {
        switch t {
        case .blue: return (p.tileTop, p.tileBottom)
        case .warn: return (HUDRenderer.rgb(0xFFC550), HUDRenderer.rgb(0xE98500))
        case .good: return (HUDRenderer.rgb(0x3EDC8A), HUDRenderer.rgb(0x0F9A52))
        case .amber: return (HUDRenderer.rgb(0xFFCF4D), HUDRenderer.rgb(0xF29200))
        case .violet: return (HUDRenderer.rgb(0xA98BFF), HUDRenderer.rgb(0x6A4BE0))
        case .gray: return p.dark ? (HUDRenderer.rgb(0x5C6A82), HUDRenderer.rgb(0x323E53)) : (HUDRenderer.rgb(0xAAB6C8), HUDRenderer.rgb(0x8291A8))
        }
    }

    /// Degradado vertical que llena `r` (dentro del recorte vigente).
    func fillVertical(_ r: CGRect, _ top: CGColor, _ bottom: CGColor, _ ctx: CGContext) {
        guard r.height > 0, let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
        ctx.restoreGState()
    }

    /// Borde luminoso: una línea fina con degradado vertical (más clara arriba).
    func glassEdge(_ r: CGRect, radius: CGFloat, top: CGColor, bottom: CGColor, width w: CGFloat, _ ctx: CGContext) {
        guard r.width > 2 * w, r.height > 2 * w else { return }
        let i = w / 2
        let rad = max(0, min(radius, r.width / 2, r.height / 2) - i)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: i, dy: i), cornerWidth: rad, cornerHeight: rad, transform: nil))
        ctx.setLineWidth(w)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        fillVertical(r, top, bottom, ctx)
        ctx.restoreGState()
    }

    /// Borde de las tarjetas de música: el mismo brillo, con el color de la portada.
    func musicEdge(_ c: MusicCardColors, _ night: Bool) -> (top: CGColor, bottom: CGColor) {
        if night {
            let light = c.accent.mixed(with: RGB(1, 1, 1), 0.35)
            return (light.cg.copy(alpha: 0.6) ?? light.cg, c.accent.cg.copy(alpha: 0.16) ?? c.accent.cg)
        }
        return (HUDRenderer.white(0.9), c.accent.cg.copy(alpha: 0.3) ?? c.accent.cg)
    }

    /// Sombra suave fuera de la tarjeta (el interior queda sin tocar, para que el vidrio deje
    /// ver el mapa).
    func paintShadow(_ r: CGRect, radius: CGFloat, color: CGColor, blur: CGFloat, drop: CGFloat, _ g: CGContext) {
        let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        g.saveGState()
        g.addRect(r.insetBy(dx: -blur * 3, dy: -blur * 3))
        g.addPath(path)
        g.clip(using: .evenOdd)
        // En un contexto de mapa de bits el desplazamiento de la sombra no gira con la
        // matriz: hacia abajo en la imagen final es negativo.
        g.setShadow(offset: CGSize(width: 0, height: -drop), blur: blur, color: color)
        g.addPath(path)
        g.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        g.fillPath()
        g.restoreGState()
    }

    /// Dibuja la tarjeta de vidrio en un contexto (lo usan la imagen guardada y el dibujo directo).
    private func paintGlass(_ r: CGRect, radius rad: CGFloat, _ p: HUDPalette, shadow: Bool, body: Bool, _ g: CGContext) {
        if shadow { paintShadow(r, radius: rad, color: p.shadow, blur: 9 * k, drop: 3 * k, g) }
        guard body else { return }
        if p.halo.alpha > 0.001 {
            // Halo azul muy suave alrededor (el brillo de las tarjetas de la referencia).
            for (out, width, a) in [(CGFloat(1.5), CGFloat(3), CGFloat(1)), (CGFloat(3.5), CGFloat(3), CGFloat(0.45))] {
                g.saveGState()
                g.addPath(CGPath(roundedRect: r.insetBy(dx: -out * k, dy: -out * k), cornerWidth: rad + out * k, cornerHeight: rad + out * k, transform: nil))
                g.setStrokeColor(p.halo.copy(alpha: p.halo.alpha * a) ?? p.halo)
                g.setLineWidth(width * k)
                g.strokePath()
                g.restoreGState()
            }
        }
        g.saveGState()
        g.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
        g.clip()
        fillVertical(r, p.cardTop, p.cardBottom, g)
        g.restoreGState()
        glassEdge(r, radius: rad, top: p.edgeTop, bottom: p.edgeBottom, width: 1.25 * k, g)
        // Brillo interior junto al borde: da el grosor del vidrio.
        let inner = 1.25 * k
        glassEdge(r.insetBy(dx: inner, dy: inner), radius: max(0, rad - inner), top: p.edgeTop.copy(alpha: p.edgeTop.alpha * 0.28) ?? p.edgeTop,
                  bottom: p.edgeBottom.copy(alpha: 0) ?? p.edgeBottom, width: 2 * k, g)
    }

    /// Tarjeta de vidrio (la pieza común de todo el panel). `body: false` dibuja solo la sombra
    /// (para tarjetas con fondo propio, como la de música).
    func glassCard(_ r: CGRect, radius: CGFloat, _ p: HUDPalette, _ ctx: CGContext, shadow: Bool = true, body: Bool = true) {
        guard r.width > 2, r.height > 2 else { return }
        let rad = max(0, min(radius, r.width / 2, r.height / 2))
        // Margen para la sombra y el halo (que sale hasta 5 px fuera de la tarjeta).
        let m = ((shadow ? 30 : 8) * k).rounded(.up)
        let w = Int((r.width + 2 * m).rounded(.up))
        let h = Int((r.height + 2 * m).rounded(.up))
        guard HUDRenderer.cacheCards, w > 0, h > 0, w * h < 1_200_000 else {
            paintGlass(r, radius: rad, p, shadow: shadow, body: body, ctx)
            return
        }
        // La parte decimal de la posición se respeta dentro de la imagen guardada.
        let fx = r.minX - r.minX.rounded(.down)
        let fy = r.minY - r.minY.rounded(.down)
        let key = String(format: "%.2f|%.2f|%.2f|%.2f|%.2f|%d%d%d", r.width, r.height, rad, fx, fy, p.dark ? 1 : 0, shadow ? 1 : 0, body ? 1 : 0)
        var image = cardImages[key]
        if image == nil {
            let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            if let off = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) {
                off.clear(CGRect(x: 0, y: 0, width: w, height: h))
                off.translateBy(x: 0, y: CGFloat(h))
                off.scaleBy(x: 1, y: -1)
                paintGlass(CGRect(x: m + fx, y: m + fy, width: r.width, height: r.height), radius: rad, p, shadow: shadow, body: body, off)
                image = off.makeImage()
                if cardImages.count > 40 { cardImages.removeAll() }
                cardImages[key] = image
            }
        }
        guard let img = image else {
            paintGlass(r, radius: rad, p, shadow: shadow, body: body, ctx)
            return
        }
        let ox = r.minX.rounded(.down) - m
        let oy = r.minY.rounded(.down) - m
        ctx.saveGState()
        ctx.translateBy(x: ox, y: oy + CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    /// Mosaico de icono: degradado, brillo de vidrio arriba y borde claro.
    func iconTile(_ r: CGRect, _ colors: (CGColor, CGColor), _ ctx: CGContext, radius: CGFloat? = nil) {
        guard r.width > 2, r.height > 2 else { return }
        let rad = radius ?? min(r.width, r.height) * 0.26
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
        ctx.clip()
        fillVertical(r, colors.0, colors.1, ctx)
        fillVertical(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.52), HUDRenderer.white(0.2), HUDRenderer.white(0), ctx)
        ctx.restoreGState()
        glassEdge(r, radius: rad, top: HUDRenderer.white(0.55), bottom: HUDRenderer.white(0.08), width: max(1, 1.1 * k), ctx)
    }

    /// Píldora ámbar de las etiquetas de estado (DEMO, SIMULACIÓN, MAPA SIMPLE…).
    func tagPill(_ r: CGRect, _ ctx: CGContext) {
        iconTile(r, (HUDRenderer.rgb(0xFFCB57), HUDRenderer.rgb(0xF2A10F)), ctx, radius: r.height / 2)
    }

    /// Reloj pequeño (círculo y agujas) para distinguir la hora actual de la de llegada.
    func clockGlyph(_ r: CGRect, _ color: CGColor, _ ctx: CGContext) {
        let lw = max(1, r.width * 0.12)
        let c = CGPoint(x: r.midX, y: r.midY)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.strokeEllipse(in: r.insetBy(dx: lw / 2, dy: lw / 2))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x, y: c.y - r.height * 0.28))
        ctx.addLine(to: c)
        ctx.addLine(to: CGPoint(x: c.x + r.width * 0.2, y: c.y + r.height * 0.08))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Campana (avisos).
    func bellGlyph(_ r: CGRect, _ color: CGColor, _ ctx: CGContext) {
        let w = r.width
        let h = r.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX + w * 0.14, y: r.minY + h * 0.76))
        path.addLine(to: CGPoint(x: r.minX + w * 0.22, y: r.minY + h * 0.62))
        path.addLine(to: CGPoint(x: r.minX + w * 0.22, y: r.minY + h * 0.42))
        path.addCurve(to: CGPoint(x: r.minX + w * 0.78, y: r.minY + h * 0.42),
                      control1: CGPoint(x: r.minX + w * 0.22, y: r.minY + h * 0.06),
                      control2: CGPoint(x: r.minX + w * 0.78, y: r.minY + h * 0.06))
        path.addLine(to: CGPoint(x: r.minX + w * 0.78, y: r.minY + h * 0.62))
        path.addLine(to: CGPoint(x: r.minX + w * 0.86, y: r.minY + h * 0.76))
        path.closeSubpath()
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.fillEllipse(in: CGRect(x: r.midX - w * 0.11, y: r.minY + h * 0.78, width: w * 0.22, height: h * 0.16))
        ctx.restoreGState()
    }

    /// Ondas de Wi-Fi (conexión con la moto).
    func linkGlyph(_ r: CGRect, _ color: CGColor, _ ctx: CGContext) {
        let w = r.width
        let base = CGPoint(x: r.midX, y: r.minY + r.height * 0.8)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(w * 0.11)
        ctx.setLineCap(.round)
        for radius in [w * 0.28, w * 0.5] {
            ctx.beginPath()
            ctx.addArc(center: base, radius: radius, startAngle: -.pi * 0.78, endAngle: -.pi * 0.22, clockwise: false)
            ctx.strokePath()
        }
        ctx.fillEllipse(in: CGRect(x: base.x - w * 0.08, y: base.y - w * 0.08, width: w * 0.16, height: w * 0.16))
        ctx.restoreGState()
    }

    /// Batería con su carga.
    func batteryGlyph(_ r: CGRect, _ color: CGColor, _ ctx: CGContext) {
        let w = r.width
        let body = CGRect(x: r.minX + w * 0.08, y: r.midY - w * 0.22, width: w * 0.74, height: w * 0.44)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(w * 0.08)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: w * 0.08, cornerHeight: w * 0.08, transform: nil))
        ctx.strokePath()
        ctx.fill(CGRect(x: body.maxX + w * 0.03, y: r.midY - w * 0.09, width: w * 0.07, height: w * 0.18))
        ctx.fill(CGRect(x: body.minX + w * 0.1, y: body.minY + w * 0.1, width: body.width * 0.28, height: body.height - w * 0.2))
        ctx.restoreGState()
    }

    // MARK: - Mapa completo con tarjetas

    /// Fondo de las tarjetas flotantes (0.6.3: la tarjeta de vidrio del sistema visual).
    func cardBackground(_ r: CGRect, _ p: HUDPalette, _ ctx: CGContext, radius: CGFloat? = nil) {
        glassCard(r, radius: radius ?? 16 * k, p, ctx)
    }

    /// Mapa en toda el área y las tarjetas encima. Devuelve true si se dibujó el mapa de calles.
    @discardableResult
    func drawOverlay(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ area: CGRect, _ ctx: CGContext) -> Bool {
        let n = s.nav
        let o = s.layout.overlay
        let cards = DashLayoutEngine.overlayCards(o, in: area, k: k, showNotices: !s.notices.isEmpty)
        let compass = cards.first { $0.item == .compass }?.rect
        // 0.8.1: señal del límite de velocidad junto a la brújula, sin tapar ninguna tarjeta.
        let sign = n.navigating && !n.arrived && n.speedLimit > 0
            ? compass.flatMap { signRect(near: $0, zone: area, busy: cards.filter { $0.item != .compass }.map { $0.rect }) } : nil
        let busyCards = cards.filter { $0.item != .compass }.map { $0.rect } + (statusReserve.map { [$0] } ?? [])
        brandSpot = brandRect(above: sign ?? compass, zone: area, busy: busyCards)
        mapAvoid = cards.map { $0.rect } + (statusReserve.map { [$0] } ?? []) + (sign.map { [$0] } ?? []) + (brandSpot.map { [$0] } ?? [])
        var streets = drawStreetMap(s, p, now, area, ctx, compass: compass)
        mapAvoid = []
        if !streets {
            streets = false
            miniCompass = false
            let anchor = CGPoint(x: area.midX, y: area.minY + area.height * 0.7)
            drawMiniMap(n, p, now, area, ctx, anchor: anchor, unit: k, divider: false)
            miniCompass = true
            if let c = compass, n.navigating {
                drawCompass(in: c, angle: CGFloat(-lastBearing), p, ctx)
            }
        }
        for card in cards {
            let r = card.rect
            textBox = r
            defer { textBox = nil }
            switch card.item {
            case .maneuver:
                drawManeuverCard(s, p, now, r, top: o.maneuverSpot.isTop, ctx)
            case .music:
                dashPlayer(s, p, now, r, ctx, card: o.musicSize)
            case .trip:
                dashTripPill(n, p, now, r, ctx)
            case .notices:
                if let note = s.notices.max(by: { $0.time < $1.time }) {
                    cardBackground(r, p, ctx, radius: 14 * k)
                    dashNoticeCard(note, s.privacy, p, now, r, ctx)
                }
            case .clock:
                dashClockPill(p, now, r, ctx)
            case .time:
                dashStatusClock(p, now, r, ctx)
            case .compass:
                break
            }
        }
        if let sign = sign {
            drawSpeedLimit(n.speedLimit, over: n.speed * 3.6 > Double(n.speedLimit) + 5, in: sign, ctx)
        }
        if let b = brandSpot { drawBrand(in: b, night: s.night, ctx) }
        brandSpot = nil
        return streets
    }

    /// Colores de la tarjeta de música en este instante (con la transición entre canciones).
    func musicColors(_ s: DashSnapshot) -> MusicCardColors {
        let spotify = s.music.source == "Spotify"
        let to = MusicCardColors.make(style: s.musicStyle, palette: s.music.palette, night: s.night, intensity: s.musicIntensity, spotify: spotify)
        guard s.paletteFade < 1 else { return to }
        let from = MusicCardColors.make(style: s.musicStyle, palette: s.paletteFrom, night: s.night, intensity: s.musicIntensity, spotify: spotify)
        return from.mixed(with: to, max(0, s.paletteFade))
    }

    /// Fondo degradado de la tarjeta de música.
    func drawMusicBackground(_ r: CGRect, _ c: MusicCardColors, radius: CGFloat, alpha: CGFloat, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        let colors = [c.top.cg.copy(alpha: alpha) ?? c.top.cg, c.bottom.cg.copy(alpha: alpha) ?? c.bottom.cg] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        }
        ctx.restoreGState()
        if radius > 0 {
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setStrokeColor(c.text.cg.copy(alpha: 0.1) ?? c.text.cg)
            ctx.setLineWidth(1)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Color del nombre del servicio. Spotify, según sus reglas de marca: verde solo sobre
    /// negro; sobre cualquier otro fondo, en blanco o negro (monocromo).
    func sourceColor(_ m: MusicSnapshot, _ c: MusicCardColors) -> CGColor {
        guard m.source == "Spotify" else { return c.accent.cg }
        let mid = c.top.mixed(with: c.bottom, 0.5)
        let black = c.top.chroma < 0.05 && c.bottom.chroma < 0.05 && mid.luminance < 0.03
        if black { return RGB(hex: 0x1ED760).cg }
        return mid.luminance < 0.4 ? RGB(1, 1, 1).cg : RGB(0, 0, 0).cg
    }

    /// Guía en otra app: la tarjeta dice cuál, el destino y la distancia en línea recta. 0.6.3:
    /// el mosaico se ajusta al tamaño de la tarjeta y el destino puede ocupar dos líneas.
    func dashExternalCard(_ ext: ExternalGuide, _ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let pad = 10 * k
        let t = min(r.height - 2 * pad, 64 * k, r.width * 0.2)
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
        iconTile(tile, tileColors(.blue, p), ctx)
        let tx = tile.maxX + 11 * k
        let tw = r.maxX - pad - tx
        // Flecha hacia el destino, en el sentido del mapa (arriba = hacia donde vas).
        if let here = s.nav.here {
            let dy = (ext.destination.lat - here.lat) * 110_574.0
            let dx = (ext.destination.lon - here.lon) * 111_320.0 * cos(here.lat * .pi / 180)
            var bearing = atan2(dx, dy)
            if !s.mapSettings.northUp && s.nav.course >= 0 { bearing -= s.nav.course * .pi / 180 }
            ctx.saveGState()
            ctx.translateBy(x: tile.midX, y: tile.midY)
            ctx.rotate(by: CGFloat(bearing))
            let a = tile.width * 0.3
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: -a))
            ctx.addLine(to: CGPoint(x: a * 0.7, y: a * 0.75))
            ctx.addLine(to: CGPoint(x: 0, y: a * 0.35))
            ctx.addLine(to: CGPoint(x: -a * 0.7, y: a * 0.75))
            ctx.closePath()
            ctx.setFillColor(p.onAccent)
            ctx.fillPath()
            ctx.restoreGState()
            let km = hypot(dx, dy)
            var y = paragraph("Guía en \(ext.provider.title)", sizes: [12.5 * k, 11.5 * k], bold: true, color: p.accent, x: tx, top: r.minY + pad - 1 * k,
                              width: tw, maxLines: 1, ctx)
            y = paragraph(ext.name, sizes: [17 * k, 15.5 * k, 14 * k], bold: true, color: p.text, x: tx, top: y + 2 * k, width: tw,
                          maxLines: r.height >= 90 * k ? 2 : 1, ctx)
            if r.maxY - pad - y >= 12 * k {
                paragraph("A \(HUDFormat.distance(km)) en línea recta", sizes: [12.5 * k, 11.5 * k, 10.5 * k], bold: false, color: p.dim,
                          x: tx, top: y + 2 * k, width: tw, maxLines: 1, ctx)
            }
        } else {
            let y = paragraph("Guía en \(ext.provider.title)", sizes: [16 * k, 14 * k], bold: true, color: p.text, x: tx, top: r.minY + pad,
                              width: tw, maxLines: 1, ctx)
            paragraph(ext.name, sizes: [14 * k, 12.5 * k], bold: false, color: p.dim, x: tx, top: y + 3 * k, width: tw, maxLines: 2, ctx)
        }
    }

    /// Datos del viaje (0.6.3, como en la referencia): tres bloques «Distancia | Restante |
    /// Llegada», cada uno con su cifra en grande y su nombre debajo, y el avance en el borde de
    /// abajo. Sin ruta no se dibuja: la hora actual está siempre arriba a la derecha y no se
    /// confunde con la llegada.
    func dashTripPill(_ n: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        guard n.navigating && !n.arrived else { return }
        drawTripBlocks(n, p, r, value: 18.5 * k, card: true, progress: true, ctx)
    }

    /// Los tres bloques del viaje dentro de `r`. `card`: con su tarjeta de vidrio (sobre el
    /// mapa); sin ella, dentro de una zona del panel. Las cifras se achican todas a la vez si
    /// alguna no cabe en su bloque.
    func drawTripBlocks(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, value: CGFloat, card: Bool, progress: Bool, _ ctx: CGContext) {
        let radius = min(14 * k, r.height / 2)
        if card { glassCard(r, radius: radius, p, ctx) }
        let t = HUDFormat.tripParts(n)
        let items: [(value: String, suffix: String, label: String)] = [
            (t.distance, "", "Distancia"), (t.remaining, "", "Restante"), (t.eta, t.suffix, t.label),
        ]
        let cw = r.width / 3
        var v = value
        func widths(_ v: CGFloat) -> [CGFloat] {
            items.map { item in
                measure(item.value, size: v, bold: true, color: p.text).width
                    + (item.suffix.isEmpty ? 0 : v * 0.14 + measure(item.suffix, size: v * 0.56, bold: true, color: p.dim).width)
            }
        }
        if let widest = widths(v).max(), widest > cw - 14 * k, widest > 0 {
            v *= max(0.62, (cw - 14 * k) / widest)
        }
        let labelSize = max(9.5 * k, v * 0.6)
        let sample = measure("0", size: v, bold: true, color: p.text)
        let sampleLabel = measure("D", size: labelSize, bold: false, color: p.dim)
        let gap = 1.5 * k
        let block = sample.ascent + sample.descent + gap + sampleLabel.ascent + sampleLabel.descent
        let lift: CGFloat = progress ? 1.5 * k : 0
        let top = r.midY - block / 2 - lift
        let valueBase = top + sample.ascent
        let labelBase = valueBase + sample.descent + gap + sampleLabel.ascent
        for (i, item) in items.enumerated() {
            let cx = r.minX + cw * (CGFloat(i) + 0.5)
            let vm = measure(item.value, size: v, bold: true, color: p.text)
            let sm = item.suffix.isEmpty ? nil : measure(item.suffix, size: v * 0.56, bold: true, color: p.dim)
            let total = vm.width + (sm.map { v * 0.14 + $0.width } ?? 0)
            put(vm, x: cx - total / 2, baseline: valueBase, ctx)
            if let sm = sm { put(sm, x: cx - total / 2 + vm.width + v * 0.14, baseline: valueBase, ctx) }
            let lm = measure(item.label, size: labelSize, bold: false, color: p.dim)
            put(lm, x: cx - lm.width / 2, baseline: labelBase, ctx)
            if i > 0 {
                let x = r.minX + cw * CGFloat(i)
                ctx.setFillColor(p.divider)
                ctx.fill(CGRect(x: x - 0.5 * k, y: r.midY - lift - r.height * 0.27, width: 1 * k, height: r.height * 0.54))
            }
        }
        guard progress else { return }
        let f = CGFloat(max(0, min(1, n.fraction)))
        let track = CGRect(x: r.minX + radius, y: r.maxY - 4 * k, width: r.width - 2 * radius, height: 2 * k)
        fillRounded(track, radius: 1 * k, color: p.divider, ctx)
        if f > 0.01 {
            let done = CGRect(x: track.minX, y: track.minY, width: max(2 * k, track.width * f), height: track.height)
            fillRounded(done.insetBy(dx: -1 * k, dy: -1 * k), radius: 2 * k, color: p.accent.copy(alpha: 0.3) ?? p.accent, ctx)
            fillRounded(done, radius: 1 * k, color: p.accent, ctx)
        }
    }

    /// La hora actual (0.6.2): pequeña y siempre en el mismo sitio, arriba a la derecha.
    func dashStatusClock(_ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let previousBox = textBox
        textBox = r
        defer { textBox = previousBox }
        let c = HUDFormat.clock(now)
        glassCard(r, radius: r.height / 2, p, ctx)
        // 0.6.3: con el símbolo del reloj, para que no se confunda con la hora de llegada (que
        // va siempre con la palabra «Llegada» en los datos del viaje).
        let t = measure(c.time, size: 17.5 * k, bold: true, color: p.text)
        let sfx = measure(c.suffix, size: 10.5 * k, bold: true, color: p.dim)
        let g = 11 * k
        let total = g + 5 * k + t.width + 3 * k + sfx.width
        let x = r.midX - total / 2
        let base = r.midY + (t.ascent - t.descent) / 2
        clockGlyph(CGRect(x: x, y: r.midY - g / 2, width: g, height: g), p.dim, ctx)
        put(t, x: x + g + 5 * k, baseline: base, ctx)
        put(sfx, x: x + g + 5 * k + t.width + 3 * k, baseline: base, ctx)
    }

    /// La parte de una zona que queda por debajo de la hora (si la hora cae en ella).
    func belowStatus(_ r: CGRect) -> CGRect {
        guard let c = statusReserve, c.intersects(r) else { return r }
        let top = c.maxY + 4 * k
        return CGRect(x: r.minX, y: top, width: r.width, height: max(0, r.maxY - top))
    }

    func dashClockPill(_ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let c = HUDFormat.clock(now)
        let t = measure(c.time, size: 24 * k, bold: true, color: p.text)
        let sfx = measure(c.suffix, size: 13 * k, bold: true, color: p.dim)
        let g = 15 * k
        let w = min(r.width, g + 6 * k + t.width + sfx.width + 40 * k)
        let pill = CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height)
        glassCard(pill, radius: r.height / 2, p, ctx)
        let x = pill.midX - (g + 6 * k + t.width + 5 * k + sfx.width) / 2
        let base = pill.midY + (t.ascent - t.descent) / 2
        clockGlyph(CGRect(x: x, y: pill.midY - g / 2, width: g, height: g), p.dim, ctx)
        put(t, x: x + g + 6 * k, baseline: base, ctx)
        put(sfx, x: x + g + 6 * k + t.width + 5 * k, baseline: base, ctx)
    }

    /// Quién envía cada aviso (0.6.3: se muestra en la lista de avisos).
    func noticeSender(_ kind: NoticeKind) -> String {
        switch kind {
        case .nav: return "NAVEGACIÓN"
        case .link: return "MOTO"
        case .battery: return "IPHONE"
        case .test: return "MOTOLINK"
        }
    }

    /// Cuánto hace del aviso: «Ahora», «4 min», «2 h».
    func noticeAge(_ note: NoticeSnapshot, _ now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSinceReferenceDate - note.time) / 60)
        if minutes < 1 { return "Ahora" }
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }

    /// El aviso más reciente como tarjeta flotante (0.6.3, como la de la referencia): icono en
    /// su mosaico, título en negrita con la hora a la derecha y el mensaje debajo.
    func dashNoticeCard(_ note: NoticeSnapshot, _ privacy: Bool, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let pad = 10 * k
        let side = min(r.height - 2 * pad, 38 * k)
        let ic = CGRect(x: r.minX + pad, y: r.midY - side / 2, width: side, height: side)
        dashNoticeIcon(note.kind, ic, p, ctx)
        let tx = ic.maxX + 10 * k
        let tw = r.maxX - pad - tx
        let age = measure(noticeAge(note, now), size: 11.5 * k, bold: false, color: p.dim)
        let top = r.midY - 18 * k
        put(age, x: r.maxX - pad - age.width, baseline: top + 1.5 * k + age.ascent, ctx)
        wrapped(note.title, sizes: [15.5 * k, 14 * k, 13 * k], color: p.text, x: tx, top: top, width: tw - age.width - 8 * k, maxLines: 1, ctx)
        textLine(privacy ? "Contenido oculto" : note.text, sizes: [13.5 * k, 12.5 * k, 11.5 * k], bold: false, color: p.dim,
                 x: tx, top: top + 21 * k, width: tw, ctx)
    }

    /// Una línea de texto (prueba tamaños de mayor a menor; si ni así cabe, termina en «…»).
    /// Devuelve el ancho dibujado.
    @discardableResult
    func textLine(_ text: String, sizes: [CGFloat], bold: Bool, color: CGColor, x: CGFloat, top: CGFloat, width: CGFloat,
                  _ ctx: CGContext, align: CGFloat = 0) -> CGFloat {
        let t = textLines(text, sizes: sizes, bold: bold, color: color, width: width, maxLines: 1)
        guard let line = t.lines.first else { return 0 }
        put(line, x: x + (width - line.width) * align, baseline: top + line.ascent, ctx)
        return line.width
    }

    /// Franja con el próximo giro para los diseños sin mapa (por ejemplo, el de música).
    func dashTurnStrip(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        glassCard(r, radius: 14 * k, p, ctx, shadow: false)
        let look = maneuverLook(n, p, street: false)
        let t = r.height - 16 * k
        let tile = CGRect(x: r.minX + 8 * k, y: r.minY + 8 * k, width: t, height: t)
        iconTile(tile, look.tile, ctx)
        HUDIcons.draw(look.kind, in: tile.insetBy(dx: t * 0.15, dy: t * 0.15), color: p.onAccent, hole: look.tile.1, ctx: ctx)
        let big = measure(look.big, size: (look.unit.isEmpty ? 22 : 30) * k, bold: true, color: p.text)
        let unit = measure(look.unit, size: 15 * k, bold: false, color: p.dim)
        let x = tile.maxX + 12 * k
        let base = r.midY + (big.ascent - big.descent) / 2
        put(big, x: x, baseline: base, ctx)
        if !look.unit.isEmpty { put(unit, x: x + big.width + 4 * k, baseline: base, ctx) }
        let lx = x + big.width + (look.unit.isEmpty ? 0 : unit.width + 4 * k) + 16 * k
        ctx.setFillColor(p.divider)
        ctx.fill(CGRect(x: lx - 8.5 * k, y: r.midY - r.height * 0.26, width: 1 * k, height: r.height * 0.52))
        wrapped(look.line, sizes: [19 * k, 17 * k, 15 * k], color: look.lineColor, x: lx, top: r.midY - 11.5 * k, width: r.maxX - 12 * k - lx, maxLines: 1, ctx)
    }

    // MARK: - Navegación

    func dashMap(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext, anchorX: CGFloat = 0.5,
                 compassBottom: Bool = false, compassLift: CGFloat = 0, compassRect: CGRect? = nil) {
        let size = 40 * k
        let compass = compassRect ?? (compassBottom
            ? CGRect(x: r.maxX - size - 10 * k, y: r.maxY - size - 10 * k - compassLift, width: size, height: size)
            : CGRect(x: r.maxX - size - 10 * k, y: r.minY + 10 * k + compassDrop, width: size, height: size))
        if drawStreetMap(s, p, now, r, ctx, compass: compass) { return }
        let u = max(0.5, min(r.width, r.height) / 400)
        let anchor = CGPoint(x: r.minX + r.width * anchorX, y: r.maxY - r.height * 0.24)
        drawMiniMap(s.nav, p, now, r, ctx, anchor: anchor, unit: u, divider: false)
    }

    /// Navegación dentro de una zona (pantalla dividida y diseños por zonas). 0.6.3: la tarjeta
    /// de la maniobra es la misma que sobre el mapa completo (compacta 200×96 o grande), en la
    /// esquina y con el tamaño elegidos en el iPhone; la barra del viaje va en el borde
    /// contrario y es más baja. Antes la tarjeta ocupaba todo el ancho y el 40 % del alto.
    func dashNav(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let n = s.nav
        let o = s.layout.overlay
        let showTrip = n.navigating && !n.arrived
        let L = NavZoneLayout.make(r, o, k: k, reserve: statusReserve, trip: showTrip)
        let sign = showTrip && n.speedLimit > 0 ? speedSignRect(L, zone: r) : nil
        brandSpot = brandRect(above: sign ?? L.compass, zone: r,
                              busy: [L.card] + (showTrip ? [L.trip] : []) + (statusReserve.map { [$0] } ?? []))
        mapAvoid = [L.card, L.compass] + (showTrip ? [L.trip] : []) + (statusReserve.map { [$0] } ?? []) + (sign.map { [$0] } ?? [])
            + (brandSpot.map { [$0] } ?? [])
        dashMap(s, p, now, r, ctx, anchorX: 0.5, compassRect: L.compass)
        mapAvoid = []
        if let sign = sign {
            drawSpeedLimit(n.speedLimit, over: n.speed * 3.6 > Double(n.speedLimit) + 5, in: sign, ctx)
        }
        if let b = brandSpot { drawBrand(in: b, night: s.night, ctx) }
        brandSpot = nil
        let zoneBox = textBox
        textBox = L.card
        drawManeuverCard(s, p, now, L.card, top: o.maneuverSpot.isTop, ctx)
        if showTrip {
            // Abajo, a la derecha: el logotipo de Mapas de Apple (abajo a la izquierda) queda a la vista.
            textBox = L.trip
            drawTripBlocks(n, p, L.trip, value: 16 * k, card: true, progress: false, ctx)
        }
        textBox = zoneBox
    }

    /// 0.8.1: lugar de la señal de velocidad máxima: junto a la brújula (encima si la brújula
    /// está abajo, debajo si está arriba; si no cabe, a su izquierda).
    func speedSignRect(_ L: NavZoneLayout, zone: CGRect) -> CGRect? {
        signRect(near: L.compass, zone: zone, busy: [L.card, L.trip] + (statusReserve.map { [$0] } ?? []))
    }

    /// Un sitio libre de 44×44 junto a la brújula: encima o debajo (hacia el centro de la zona)
    /// y, si no cabe, a su lado.
    func signRect(near c: CGRect, zone: CGRect, busy: [CGRect]) -> CGRect? {
        guard !c.isEmpty else { return nil }
        let size = 44 * k
        let gap = 6 * k
        let below = c.midY < zone.midY
        let inward = c.midX > zone.midX ? c.minX - gap - size : c.maxX + gap
        let candidates = [
            CGRect(x: c.midX - size / 2, y: below ? c.maxY + gap : c.minY - gap - size, width: size, height: size),
            CGRect(x: inward, y: c.midY - size / 2, width: size, height: size),
            CGRect(x: c.midX - size / 2, y: below ? c.minY - gap - size : c.maxY + gap, width: size, height: size),
        ]
        let others = busy.filter { !$0.isEmpty }
        return candidates.first { cand in
            zone.contains(cand) && !others.contains { $0.intersects(cand.insetBy(dx: -3 * k, dy: -3 * k)) }
        }
    }

    /// 0.8.1: señal redonda de velocidad máxima (aro rojo). Si se va más de 5 km/h por encima,
    /// se llena de rojo. Es un dibujo de la app sobre su propio mapa: no toca el velocímetro ni
    /// los indicadores de la moto.
    func drawSpeedLimit(_ kmh: Int, over: Bool, in r: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        let red = CGColor(red: 0.86, green: 0.1, blue: 0.12, alpha: 1)
        ctx.setShadow(offset: CGSize(width: 0, height: 2 * k), blur: 6 * k, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(over ? red : CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: r)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        let ring = 4.5 * k
        ctx.setStrokeColor(red)
        ctx.setLineWidth(ring)
        ctx.strokeEllipse(in: r.insetBy(dx: ring / 2, dy: ring / 2))
        ctx.restoreGState()
        let text = "\(kmh)"
        let size = (kmh >= 100 ? 15 : 18) * k
        let m = measure(text, size: size, bold: true, color: over ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0.05, alpha: 1))
        put(m, x: r.midX - m.width / 2, baseline: r.midY + (m.ascent - m.descent) / 2, ctx)
    }

    /// La tarjeta de la maniobra (sobre el mapa completo y en las zonas con mapa): misma forma
    /// en todos los modos. Sin ruta o con la guía en otra app se dibuja más baja, pegada al borde
    /// donde está.
    func drawManeuverCard(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, top: Bool, _ ctx: CGContext) {
        let n = s.nav
        let compact = s.layout.overlay.maneuverSize == .compact
        let radius = 16 * k
        func shortCard(_ h: CGFloat) -> CGRect {
            let hh = min(r.height, h)
            return CGRect(x: r.minX, y: top ? r.minY : r.maxY - hh, width: r.width, height: hh)
        }
        if let ext = s.external, !n.navigating {
            let small = shortCard(112 * k)
            glassCard(small, radius: radius, p, ctx)
            dashExternalCard(ext, s, p, now, small, ctx)
        } else if n.navigating || n.arrived || !n.previewRoutes.isEmpty {
            glassCard(r, radius: radius, p, ctx)
            if compact { dashTurnCompact(n, p, r, ctx) } else { dashTurnContent(n, p, r, ctx) }
        } else {
            let small = shortCard((compact ? 66 : 92) * k)
            glassCard(small, radius: radius, p, ctx)
            if compact { dashTurnCompact(n, p, small, ctx) } else { dashTurnContent(n, p, small, ctx) }
        }
    }

    func dashTurn(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        dashTurnContent(n, p, r, ctx)
    }

    /// Lo que dice la tarjeta de la maniobra en cada caso: en ruta, recalculando, ruta propuesta,
    /// llegada o sin ruta. `street`: solo la calle (en la tarjeta compacta el giro lo dice la
    /// flecha).
    struct ManeuverLook {
        var tile: (CGColor, CGColor)
        var kind: ManeuverKind
        var big: String
        var unit: String
        var line: String
        var lineColor: CGColor
        var then: ManeuverKind?
        var idle: Bool
    }

    func maneuverLook(_ n: HUDSnapshot, _ p: HUDPalette, street: Bool) -> ManeuverLook {
        let preview = !n.navigating && n.previewRoutes.indices.contains(n.previewSelected)
        var look = ManeuverLook(tile: tileColors(.blue, p), kind: n.kind, big: "", unit: "",
                                line: street ? (HUDFormat.street(from: n.instruction) ?? n.instruction) : n.instruction,
                                lineColor: p.text, then: nil, idle: false)
        if n.arrived {
            look.tile = tileColors(.good, p)
            look.kind = .arrive
            look.big = "Llegaste"
            look.line = n.destinationName
        } else if preview {
            let i = n.previewSelected
            let parts = HUDFormat.distanceParts(n.previewDistances.indices.contains(i) ? n.previewDistances[i] : 0)
            look.big = parts.value
            look.unit = parts.unit
            look.kind = .depart
            var text = n.previewRoutes.count > 1 ? "Ruta \(i + 1) de \(n.previewRoutes.count)" : "Ruta lista"
            if n.previewTimes.indices.contains(i) { text += " · " + HUDFormat.durationCompact(n.previewTimes[i]) }
            look.line = street ? text : text + " · Toca Iniciar en el iPhone"
        } else if !n.navigating {
            look.tile = tileColors(.gray, p)
            look.kind = .depart
            look.big = "Sin ruta"
            look.line = "Elige un destino en el iPhone"
            look.lineColor = p.dim
            look.idle = true
        } else {
            let parts = HUDFormat.distanceParts(n.distanceToManeuver)
            look.big = parts.value
            look.unit = parts.unit
            if n.rerouting {
                look.tile = tileColors(.warn, p)
                look.line = street ? "Recalculando…" : "Recalculando la ruta…"
                look.lineColor = p.warn
            } else {
                look.then = n.thenKind
            }
        }
        return look
    }

    /// La flecha en su mosaico con degradado y brillo (como en la referencia).
    func maneuverTile(_ look: ManeuverLook, _ r: CGRect, _ p: HUDPalette, _ ctx: CGContext) {
        iconTile(r, look.tile, ctx)
        HUDIcons.draw(look.kind, in: r.insetBy(dx: r.width * 0.15, dy: r.height * 0.15), color: p.onAccent, hole: look.tile.1, ctx: ctx)
    }

    /// La distancia en grande con su unidad, ajustada al ancho. `baseline` o, si es nil, centrada
    /// en `centerY`. Devuelve la letra usada (para colocar lo de debajo).
    @discardableResult
    func maneuverDistance(_ look: ManeuverLook, x: CGFloat, baseline: CGFloat?, centerY: CGFloat, size: CGFloat, width: CGFloat,
                          _ p: HUDPalette, _ ctx: CGContext) -> Measured {
        var s = look.unit.isEmpty ? size * 0.66 : size
        var m = measure(look.big, size: s, bold: true, color: p.text)
        var um = measure(look.unit, size: s * 0.46, bold: false, color: p.dim)
        let need = m.width + (look.unit.isEmpty ? 0 : s * 0.1 + um.width)
        if need > width, need > 0 {
            s *= max(0.5, width / need)
            m = measure(look.big, size: s, bold: true, color: p.text)
            um = measure(look.unit, size: s * 0.46, bold: false, color: p.dim)
        }
        let base = baseline ?? (centerY + (m.ascent - m.descent) / 2)
        put(m, x: x, baseline: base, ctx)
        if !look.unit.isEmpty { put(um, x: x + m.width + s * 0.1, baseline: base, ctx) }
        return m
    }

    /// La maniobra siguiente, pequeña, en un chip de vidrio.
    func thenChip(_ kind: ManeuverKind, _ r: CGRect, _ p: HUDPalette, _ ctx: CGContext) {
        let rad = r.width * 0.3
        fillRounded(r, radius: rad, color: p.text.copy(alpha: 0.1) ?? p.text, ctx)
        glassEdge(r, radius: rad, top: p.text.copy(alpha: 0.24) ?? p.text, bottom: p.text.copy(alpha: 0.05) ?? p.text, width: 1 * k, ctx)
        HUDIcons.draw(kind, in: r.insetBy(dx: r.width * 0.16, dy: r.height * 0.16), color: p.dim, hole: p.background, ctx: ctx)
    }

    /// Varias líneas de texto con o sin negrita (prueba tamaños de mayor a menor; la última
    /// línea termina en «…» si ni así cabe). Devuelve dónde acaba.
    @discardableResult
    func paragraph(_ text: String, sizes: [CGFloat], bold: Bool, color: CGColor, x: CGFloat, top: CGFloat, width: CGFloat,
                   maxLines: Int, _ ctx: CGContext, align: CGFloat = 0) -> CGFloat {
        let t = textLines(text, sizes: sizes, bold: bold, color: color, width: width, maxLines: maxLines)
        var y = top
        for (i, line) in t.lines.enumerated() {
            put(line, x: x + (width - line.width) * align, baseline: y + line.ascent, ctx)
            y += line.ascent + line.descent + (i < t.lines.count - 1 ? t.size * 0.1 : 0)
        }
        return y
    }

    /// Tarjeta grande de la maniobra y zona «Próximo giro» (0.6.3, como en la referencia): la
    /// flecha en su mosaico a la izquierda, la distancia en grande y la instrucción completa a
    /// su derecha, y la maniobra siguiente debajo de la flecha. En zonas altas y estrechas la
    /// instrucción va debajo de la flecha.
    func dashTurnContent(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        let look = maneuverLook(n, p, street: false)
        let pad = max(10 * k, min(15 * k, min(r.width, r.height) * 0.08))
        let lineSize = min(20 * k, max(14 * k, r.height * 0.115))
        if r.width >= r.height * 1.45 {
            let thenRoom: CGFloat = look.then != nil ? 30 * k : 0
            let t = max(24 * k, min(r.height - 2 * pad - thenRoom, r.width * 0.3, 100 * k))
            let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
            maneuverTile(look, tile, p, ctx)
            let tx = tile.maxX + 14 * k
            let tw = r.maxX - pad - tx
            let ds = min(t * 0.52, 46 * k, (r.height - 2 * pad) * 0.42)
            let m = maneuverDistance(look, x: tx, baseline: tile.minY + ds * 0.86, centerY: 0, size: ds, width: tw, p, ctx)
            let top = tile.minY + ds * 0.86 + m.descent + 4 * k
            let avail = r.maxY - pad - top
            let lines = max(1, min(3, Int(avail / (lineSize * 1.3))))
            if avail > lineSize {
                paragraph(look.line, sizes: [lineSize, lineSize * 0.9, lineSize * 0.82], bold: true, color: look.lineColor,
                          x: tx, top: top, width: tw, maxLines: lines, ctx)
            }
            if let then = look.then, r.maxY - pad - tile.maxY >= 24 * k {
                let chip = min(24 * k, r.maxY - pad - tile.maxY - 4 * k)
                let label = measure("Luego", size: 11.5 * k, bold: false, color: p.dim)
                let total = label.width + 6 * k + chip
                let x = tile.midX - total / 2
                let y = tile.maxY + 6 * k
                put(label, x: x, baseline: y + chip / 2 + (label.ascent - label.descent) / 2, ctx)
                thenChip(then, CGRect(x: x + label.width + 6 * k, y: y, width: chip, height: chip), p, ctx)
            }
            return
        }
        // Zona alta y estrecha: flecha y distancia arriba, instrucción debajo.
        let t = max(24 * k, min(r.height * 0.4, r.width * 0.32, 96 * k))
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
        maneuverTile(look, tile, p, ctx)
        let chip = 24 * k
        let tx = tile.maxX + 12 * k
        let tw = r.maxX - pad - tx - (look.then != nil ? chip + 6 * k : 0)
        maneuverDistance(look, x: tx, baseline: nil, centerY: tile.midY, size: min(t * 0.6, 46 * k), width: tw, p, ctx)
        if let then = look.then {
            thenChip(then, CGRect(x: r.maxX - pad - chip, y: tile.minY, width: chip, height: chip), p, ctx)
        }
        let top = tile.maxY + 10 * k
        let avail = r.maxY - pad - top
        if avail > lineSize {
            let lines = max(1, min(3, Int(avail / (lineSize * 1.3))))
            paragraph(look.line, sizes: [lineSize, lineSize * 0.9, lineSize * 0.82], bold: true, color: look.lineColor,
                      x: r.minX + pad, top: top, width: r.width - 2 * pad, maxLines: lines, ctx)
        }
    }

    /// Zona «Viaje»: los mismos tres bloques que sobre el mapa (Distancia, Restante, Llegada),
    /// más grandes, con el avance debajo. En zonas estrechas, una fila por dato.
    func dashTrip(_ n: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        guard n.navigating && !n.arrived else {
            dashClock(p, now, r, ctx)
            return
        }
        let pad = max(8 * k, min(r.width, r.height) * 0.08)
        let inner = r.insetBy(dx: pad, dy: pad)
        if inner.width >= 260 * k {
            let v = max(14 * k, min(inner.height * 0.32, inner.width / 3 * 0.24, 34 * k))
            drawTripBlocks(n, p, inner, value: v, card: false, progress: true, ctx)
            return
        }
        let t = HUDFormat.tripParts(n)
        let items: [(String, String)] = [(t.distance, "Distancia"), (t.remaining, "Restante"), (t.eta + " " + t.suffix, t.label)]
        let barH = max(3 * k, r.height * 0.03)
        let rows = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height - barH - 6 * k)
        let rh = rows.height / 3
        let vs = max(12 * k, min(rh * 0.5, inner.width * 0.16))
        for (i, item) in items.enumerated() {
            let mid = rows.minY + rh * (CGFloat(i) + 0.5)
            let v = measure(item.0, size: vs, bold: true, color: p.text)
            let l = measure(item.1, size: vs * 0.58, bold: false, color: p.dim)
            put(v, x: rows.minX, baseline: mid + (v.ascent - v.descent) / 2, ctx)
            put(l, x: rows.maxX - l.width, baseline: mid + (l.ascent - l.descent) / 2, ctx)
            if i > 0 {
                ctx.setFillColor(p.divider)
                ctx.fill(CGRect(x: rows.minX, y: rows.minY + rh * CGFloat(i) - 0.5 * k, width: rows.width, height: 1 * k))
            }
        }
        let track = CGRect(x: inner.minX, y: inner.maxY - barH, width: inner.width, height: barH)
        fillRounded(track, radius: barH / 2, color: p.divider, ctx)
        let f = CGFloat(max(0, min(1, n.fraction)))
        if f > 0.01 {
            fillRounded(CGRect(x: track.minX, y: track.minY, width: track.width * f, height: barH), radius: barH / 2, color: p.accent, ctx)
        }
    }

    func dashClock(_ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let c = HUDFormat.clock(now)
        let size = min(r.height * 0.42, r.width * 0.26)
        let t = measure(c.time, size: size, bold: true, color: p.text)
        let sfx = measure(c.suffix, size: size * 0.34, bold: true, color: p.dim)
        let total = t.width + size * 0.12 + sfx.width
        let x = r.midX - total / 2
        let base = r.midY + size * 0.12
        put(t, x: x, baseline: base, ctx)
        put(sfx, x: x + t.width + size * 0.12, baseline: base, ctx)
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_GT")
        f.dateFormat = "EEEE d 'de' MMMM"
        let d = measure(f.string(from: now), size: size * 0.3, bold: false, color: p.dim)
        if d.width < r.width - 12 {
            put(d, x: r.midX - d.width / 2, baseline: base + size * 0.5, ctx)
        }
    }

    // MARK: - Música (0.6.3: el mismo reproductor en todos los modos; 0.6.4: con botones)

    /// El reproductor en cualquier sitio: música completa, columna de la pantalla dividida o de
    /// Música + Avisos, y tarjetas sobre el mapa. Siempre el mismo fondo con los colores y la luz
    /// de la portada, la portada con sombra, la misma letra, los botones y la barra; solo cambia
    /// la forma (`MusicPlayerLayout`). 0.6.4: los botones (anterior, reproducir/pausar y
    /// siguiente) son los de la referencia y solo se ven: el protocolo de la moto no envía
    /// toques ni teclas a la app, así que la música se controla desde el iPhone.
    /// `card`: tamaño de la tarjeta sobre el mapa, o nil para una zona del panel.
    func dashPlayer(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext, card: CardSize?) {
        let m = s.music
        let c = musicColors(s)
        let L = MusicPlayerLayout.make(r, k: k, artwork: s.showArtwork, size: s.artworkSize,
                                       reserve: card == nil ? statusReserve : nil, card: card)
        // 0.6.3: sobre el mapa, la tarjeta de música lleva la misma sombra que las demás.
        if L.card { glassCard(r, radius: 18 * k, p, ctx, shadow: true, body: false) }
        drawPlayerBackground(s, c, L, r, ctx)
        let has = m.available && !m.title.isEmpty
        ctx.saveGState()
        if L.card {
            // Durante el cambio de canción los textos se desplazan: que no salgan de la tarjeta.
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 18 * k, cornerHeight: 18 * k, transform: nil))
            ctx.clip()
        }
        // Nombre del servicio arriba a la izquierda (en las filas va en la primera línea o junto a
        // los botones), con un punto del color de la barra, como la marca en la referencia.
        if L.style != .row && s.showSource && has && L.header.width > 40 * k {
            let src = textLines(sourceName(m), sizes: [L.source], bold: true, color: sourceColor(m, c), width: L.header.width - L.source, maxLines: 1)
            if let line = src.lines.first {
                let d = L.source * 0.62
                ctx.setFillColor(c.accent.cg)
                ctx.fillEllipse(in: CGRect(x: L.header.minX, y: L.header.midY - d / 2, width: d, height: d))
                put(line, x: L.header.minX + d + L.source * 0.45, baseline: L.header.midY + (line.ascent - line.descent) / 2, ctx)
            }
        }
        // Al cambiar de canción la portada se funde de una a otra; los textos, uno después del
        // otro (la anterior sale hacia arriba y la nueva entra desde abajo), sin mezclarse.
        let f = CGFloat(max(0, min(1, s.musicFade)))
        let shift = (L.style == .row ? 6 : 10) * k
        if let old = s.musicFrom, s.musicFade < 1 {
            let out = min(1, 2 * f)
            let into = max(0, 2 * f - 1)
            playerTrack(old, s, c, L, p, artAlpha: 1 - f, textAlpha: 1 - out, dy: -shift * out, art: old.artwork, artFrom: nil, artFade: 1, ctx)
            playerTrack(m, s, c, L, p, artAlpha: f, textAlpha: into, dy: shift * (1 - into), art: m.artwork, artFrom: nil, artFade: 1, ctx)
        } else {
            playerTrack(m, s, c, L, p, artAlpha: 1, textAlpha: 1, dy: 0, art: m.artwork, artFrom: s.artFrom, artFade: CGFloat(s.artFade), ctx)
        }
        playerControls(s, c, L, ctx)
        if has && s.showProgress && m.duration > 1 {
            playerProgress(m, c, L, now, ctx)
        }
        ctx.restoreGState()
        if L.card {
            let e = musicEdge(c, s.night)
            glassEdge(r, radius: 18 * k, top: e.top, bottom: e.bottom, width: 1.25 * k, ctx)
        }
    }

    /// Nombre del servicio como lo escribe cada uno («Spotify», «Apple Music»).
    func sourceName(_ m: MusicSnapshot) -> String {
        m.source.isEmpty ? "Música" : m.source
    }

    /// 0.6.4: los botones de la referencia: anterior, reproducir/pausar (el grande, en un círculo)
    /// y siguiente. Solo se ven (en la moto no se pueden pulsar). El central muestra el estado
    /// real: ❚❚ mientras suena y ▶ en pausa, con un fundido corto al cambiar. Sin música se ven
    /// apagados. De noche, iconos blancos y círculo blanco con el símbolo oscuro; de día, al revés
    /// (oscuros sobre el fondo claro), para que se distingan igual.
    func playerControls(_ s: DashSnapshot, _ c: MusicCardColors, _ L: MusicPlayerLayout, _ ctx: CGContext) {
        guard L.button > 0, !L.controls.isEmpty else { return }
        let m = s.music
        let has = m.available && !m.title.isEmpty
        let g = L.transport
        // Tarjeta compacta: el nombre del servicio, a la derecha de los botones.
        if L.sourceInControls && s.showSource && has {
            let room = L.controls.maxX - g.bounds.maxX - 10 * k
            let d = L.source * 0.6
            let gap = L.source * 0.4
            let src = textLines(sourceName(m), sizes: [L.source, L.source * 0.9], bold: true, color: sourceColor(m, c),
                                width: max(10, room - d - gap), maxLines: 1)
            if let line = src.lines.first, !line.truncated, line.width + d + gap <= room {
                let x = L.controls.maxX - line.width
                ctx.setFillColor(c.accent.cg)
                ctx.fillEllipse(in: CGRect(x: x - gap - d, y: L.controls.midY - d / 2, width: d, height: d))
                put(line, x: x, baseline: L.controls.midY + (line.ascent - line.descent) / 2, ctx)
            }
        }
        let alpha: CGFloat = has ? 1 : 0.35
        let playing = has && m.playing
        if HUDRenderer.recordText {
            let box = textBox ?? ctx.boundingBoxOfClipPath
            controlMarks.append(ControlMark(kind: "anterior", rect: g.previous, box: box, alpha: alpha))
            controlMarks.append(ControlMark(kind: playing ? "pausa" : "reproducir", rect: g.play, box: box, alpha: alpha))
            controlMarks.append(ControlMark(kind: "siguiente", rect: g.next, box: box, alpha: alpha))
        }
        if HUDRenderer.hideControls { return }
        let ink = c.text.cg
        // El símbolo del círculo: del tono del fondo, muy oscuro, sobre el círculo claro; blanco
        // sobre el círculo oscuro.
        let mid = c.top.mixed(with: c.bottom, 0.5)
        let symbol = c.text.luminance > 0.5 ? mid.with(l: min(mid.hsl.l, 0.12)).cg : RGB(1, 1, 1).cg
        ctx.saveGState()
        ctx.setAlpha(alpha)
        skipGlyph(g.previous, forward: false, ink, ctx)
        skipGlyph(g.next, forward: true, ink, ctx)
        let d = g.play.width
        paintShadow(g.play, radius: d / 2, color: CGColor(gray: 0, alpha: s.night ? 0.45 : 0.24), blur: max(3 * k, d * 0.2), drop: d * 0.06, ctx)
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: g.play)
        let fade = CGFloat(max(0, min(1, s.playFade)))
        if fade < 1 && has {
            ctx.setAlpha(alpha * (1 - fade))
            playPauseGlyph(!playing, g.play, symbol, ctx)
            ctx.setAlpha(alpha * fade)
        }
        playPauseGlyph(playing, g.play, symbol, ctx)
        ctx.restoreGState()
    }

    /// 0.6.4: icono de saltar (anterior o siguiente): barra y triángulo con las esquinas
    /// suavizadas, como los de la referencia.
    func skipGlyph(_ r: CGRect, forward: Bool, _ color: CGColor, _ ctx: CGContext) {
        guard r.width > 2, r.height > 2 else { return }
        let w = r.width
        let barW = max(1.5 * k, w * 0.18)
        let soft = max(0.6 * k, w * 0.06)
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        let bar = CGRect(x: forward ? r.maxX - barW : r.minX, y: r.minY, width: barW, height: r.height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath()
        // El triángulo apunta hacia la barra.
        let near = forward ? bar.minX - w * 0.05 - soft : bar.maxX + w * 0.05 + soft
        let far = forward ? r.minX + soft : r.maxX - soft
        ctx.setLineJoin(.round)
        ctx.setLineWidth(soft * 2)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: far, y: r.minY + soft))
        ctx.addLine(to: CGPoint(x: near, y: r.midY))
        ctx.addLine(to: CGPoint(x: far, y: r.maxY - soft))
        ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }

    /// 0.6.4: símbolo del botón central: ❚❚ mientras suena (el botón pausaría) o ▶ en pausa.
    func playPauseGlyph(_ playing: Bool, _ circle: CGRect, _ color: CGColor, _ ctx: CGContext) {
        let d = circle.width
        let c = CGPoint(x: circle.midX, y: circle.midY)
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        if playing {
            let h = d * 0.36
            let bw = d * 0.115
            let gap = d * 0.12
            for x in [c.x - gap / 2 - bw, c.x + gap / 2] {
                ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: c.y - h / 2, width: bw, height: h),
                                   cornerWidth: bw * 0.3, cornerHeight: bw * 0.3, transform: nil))
            }
            ctx.fillPath()
        } else {
            let h = d * 0.38
            let w = h * 0.88
            let soft = d * 0.025
            // Un poco a la derecha: el triángulo se ve centrado así (centro óptico).
            let x0 = c.x - w / 2 + d * 0.035
            ctx.setLineJoin(.round)
            ctx.setLineWidth(soft * 2)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x0 + soft, y: c.y - h / 2 + soft))
            ctx.addLine(to: CGPoint(x: x0 + w - soft, y: c.y))
            ctx.addLine(to: CGPoint(x: x0 + soft, y: c.y + h / 2 - soft))
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
        ctx.restoreGState()
    }

    /// Barra de progreso con el tiempo transcurrido y la duración a los lados (en la tarjeta
    /// compacta, fina, al pie y sin tiempos). 0.6.4: la parte hecha lleva un degradado del color
    /// de la barra (más claro al empezar) y el punto, un halo suave.
    func playerProgress(_ m: MusicSnapshot, _ c: MusicCardColors, _ L: MusicPlayerLayout, _ now: Date, _ ctx: CGContext) {
        let elapsed = m.playing ? max(0, now.timeIntervalSinceReferenceDate - m.positionTime) : 0
        let pos = max(0, min(m.duration, m.position + elapsed))
        let fraction = CGFloat(pos / m.duration)
        var bar = CGRect(x: L.progress.minX, y: L.progress.midY - L.bar / 2, width: L.progress.width, height: L.bar)
        if L.times {
            let a = measure(dashTime(pos), size: L.time, bold: true, color: c.secondary.cg)
            let b = measure(dashTime(m.duration), size: L.time, bold: true, color: c.secondary.cg)
            // Ancho fijo para los tiempos: la barra no se mueve al cambiar los segundos.
            let label = max(measure(m.duration >= 600 ? "88:88" : "8:88", size: L.time, bold: true, color: c.secondary.cg).width, a.width, b.width)
            let gap = (L.style == .stage ? 14 : (L.card ? 7 : 10)) * k
            bar = CGRect(x: L.progress.minX + label + gap, y: L.progress.midY - L.bar / 2,
                         width: max(0, L.progress.width - 2 * (label + gap)), height: L.bar)
            let baseline = L.progress.midY + (a.ascent - a.descent) / 2
            put(a, x: bar.minX - gap - a.width, baseline: baseline, ctx)
            put(b, x: bar.maxX + gap, baseline: baseline, ctx)
        }
        guard bar.width > 4 else { return }
        fillRounded(bar, radius: L.bar / 2, color: c.track.cg, ctx)
        let done = bar.width * fraction
        if done > 1 {
            let fill = CGRect(x: bar.minX, y: bar.minY, width: max(done, L.bar), height: bar.height)
            let light = c.text.luminance > 0.5 ? c.accent.mixed(with: RGB(1, 1, 1), 0.3) : c.accent.with(l: min(1, c.accent.hsl.l + 0.08))
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: fill, cornerWidth: L.bar / 2, cornerHeight: L.bar / 2, transform: nil))
            ctx.clip()
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [light.cg, c.accent.cg] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: bar.minX, y: bar.midY), end: CGPoint(x: fill.maxX, y: bar.midY), options: [])
            }
            ctx.restoreGState()
        }
        // Punto en la posición actual con un halo del color de la barra (referencia).
        let thin = L.card && !L.times
        let d = thin ? L.bar * 2 : max(L.bar * 2.2, 7 * k)
        let x = min(max(bar.minX + done, bar.minX + d / 2), bar.maxX - d / 2)
        let halo = thin ? d * 0.8 : d
        ctx.setFillColor(c.accent.cg.copy(alpha: 0.3) ?? c.accent.cg)
        ctx.fillEllipse(in: CGRect(x: x - halo, y: bar.midY - halo, width: halo * 2, height: halo * 2))
        ctx.setFillColor(c.text.cg)
        ctx.fillEllipse(in: CGRect(x: x - d / 2, y: bar.midY - d / 2, width: d, height: d))
    }

    func dashTime(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// `fill`: color detrás de una portada que no es cuadrada (0.6.4).
    func dashArtwork(_ image: CGImage?, _ rect: CGRect, _ p: HUDPalette, _ ctx: CGContext, fill: CGColor? = nil) {
        guard rect.width > 4 else { return }
        // Reglas de Spotify para portadas: sin recortes ni nada encima y esquinas de 4 px
        // (pequeñas) u 8 px (grandes). Se aplica igual a Apple Music.
        let radius = (rect.width < 110 ? 4 : 8) * k
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        if let image = image {
            // 0.6.4: proporciones respetadas. Las portadas de Spotify y Apple Music son cuadradas;
            // si llega una que no lo es, se ve entera (sin recortar ni estirar) sobre un fondo.
            var target = rect
            let iw = CGFloat(image.width)
            let ih = CGFloat(image.height)
            if iw > 0, ih > 0, abs(iw - ih) > max(iw, ih) * 0.02 {
                let scale = min(rect.width / iw, rect.height / ih)
                target = CGRect(x: rect.midX - iw * scale / 2, y: rect.midY - ih * scale / 2, width: iw * scale, height: ih * scale)
                ctx.setFillColor(fill ?? p.line)
                ctx.fill(rect)
            }
            ctx.translateBy(x: target.minX, y: target.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(origin: .zero, size: target.size))
        } else {
            ctx.setFillColor(p.line)
            ctx.fill(rect)
            // Nota musical.
            let w = rect.width
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + w * y) }
            ctx.setFillColor(p.dim)
            ctx.setStrokeColor(p.dim)
            ctx.setLineWidth(w * 0.06)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.fillEllipse(in: CGRect(x: rect.minX + w * 0.24, y: rect.minY + w * 0.6, width: w * 0.2, height: w * 0.16))
            ctx.fillEllipse(in: CGRect(x: rect.minX + w * 0.54, y: rect.minY + w * 0.52, width: w * 0.2, height: w * 0.16))
            ctx.beginPath()
            ctx.move(to: pt(0.41, 0.68))
            ctx.addLine(to: pt(0.41, 0.3))
            ctx.addLine(to: pt(0.71, 0.22))
            ctx.addLine(to: pt(0.71, 0.6))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Maniobra compacta

    /// Tarjeta compacta de la maniobra (200×96, la misma en todos los modos con mapa): mosaico
    /// con la flecha, la distancia en grande y la calle debajo, con márgenes justos para tapar
    /// poco mapa. La instrucción completa está en la tarjeta grande; aquí el giro lo dice la
    /// flecha.
    func dashTurnCompact(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        let pad = 10 * k
        let look = maneuverLook(n, p, street: true)
        if look.idle {
            // Sin ruta: tarjeta baja.
            let t = min(36 * k, r.height - 2 * pad)
            let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
            maneuverTile(look, tile, p, ctx)
            let tx = tile.maxX + 9 * k
            let tw = r.maxX - pad - tx
            let y = paragraph(look.big, sizes: [17 * k, 15.5 * k], bold: true, color: p.text, x: tx, top: r.minY + pad - 1 * k, width: tw, maxLines: 1, ctx)
            paragraph(look.line, sizes: [12 * k, 11 * k], bold: false, color: p.dim, x: tx, top: y + 2 * k, width: tw, maxLines: 2, ctx)
            return
        }
        let t = min(52 * k, r.height - 2 * pad - 24 * k)
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
        maneuverTile(look, tile, p, ctx)
        let chip = 22 * k
        let tx = tile.maxX + 10 * k
        let tw = r.maxX - pad - tx - (look.then != nil ? chip + 4 * k : 0)
        maneuverDistance(look, x: tx, baseline: nil, centerY: tile.midY, size: 36 * k, width: tw, p, ctx)
        if let then = look.then {
            thenChip(then, CGRect(x: r.maxX - pad - chip, y: tile.minY, width: chip, height: chip), p, ctx)
        }
        let top = tile.maxY + 5 * k
        if r.maxY - top > 12 * k {
            wrapped(look.line, sizes: [17 * k, 15.5 * k, 14 * k], color: look.lineColor, x: r.minX + pad, top: top, width: r.width - 2 * pad, maxLines: 1, ctx)
        }
    }

    // MARK: - Música completa (0.6.2)

    /// Líneas de texto ya cortadas (con "…" si no caben), para poder centrarlas.
    func textLines(_ text: String, sizes: [CGFloat], bold: Bool, color: CGColor, width: CGFloat,
                   maxLines: Int) -> (lines: [Measured], size: CGFloat, fits: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, width > 10, let smallest = sizes.last else { return ([], sizes.first ?? 0, true) }
        for size in sizes {
            let attrs = attributes(size: size, bold: bold, color: color)
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
            if start < total && size != smallest { continue }
            let fits = start >= total
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
            let out = lines.enumerated().map { i, line in
                measured(line, in: clean, range: ranges[i], truncated: cutLast && i == lines.count - 1)
            }
            return (out, size, fits)
        }
        return ([], smallest, false)
    }

    /// Fondo del reproductor: degradado con los colores de la portada y un resplandor suave
    /// detrás de ella (en las tarjetas, más pequeño y suave para que el texto se siga leyendo).
    /// 0.6.4: encima, la luz de la portada (sus colores, difuminados, como el fondo de CarPlay) y,
    /// de noche, un velo algo más oscuro abajo. Solo cambia con la canción, así que se dibuja una
    /// vez y se reutiliza; al cambiar de canción, el fondo anterior y el nuevo se funden.
    func drawPlayerBackground(_ s: DashSnapshot, _ c: MusicCardColors, _ L: MusicPlayerLayout, _ r: CGRect, _ ctx: CGContext) {
        let w = Int(r.width.rounded())
        let h = Int(r.height.rounded())
        guard w > 0, h > 0 else { return }
        let center: CGPoint
        if L.artwork.width > 0 {
            center = CGPoint(x: L.artwork.midX, y: L.artwork.midY)
        } else {
            center = L.style == .row ? CGPoint(x: r.minX + r.height / 2, y: r.midY) : CGPoint(x: r.maxX - r.width * 0.25, y: r.midY)
        }
        let radius: CGFloat = L.card ? 18 * k : 0
        let alpha: CGFloat = L.card ? 0.94 : 1
        let reach = L.style == .row ? max(L.artwork.width * 1.6, r.height) : max(r.width, r.height) * 0.55
        let strength: CGFloat = (s.night ? 0.5 : 0.4) * (L.style == .row ? 0.8 : 1) * alpha
        let dynamic = s.musicStyle == .dynamic
        let lightAlpha = (L.card ? 0.42 : 0.6) * CGFloat(max(0, min(1, s.musicIntensity / 0.75)))
        let fadeIn = CGFloat(max(0, min(1, s.paletteFade)))
        func glowColor(_ palette: ArtPalette?, _ colors: MusicCardColors) -> RGB {
            guard let base = palette?.base else { return colors.accent }
            let hsl = base.hsl
            return s.night ? RGB(h: hsl.h, s: min(hsl.s, 0.6), l: 0.42) : RGB(h: hsl.h, s: min(hsl.s, 0.6) * 0.8, l: 0.8)
        }
        func light(_ art: CGImage?) -> (image: CGImage, signature: String)? {
            guard dynamic, let art = art else { return nil }
            return ambientScaled(art, night: s.night, width: w, height: h)
        }
        // Un fondo completo: degradado, luz de la portada, resplandor y velo.
        func paint(_ g: CGContext, _ colors: MusicCardColors, _ glow: RGB, _ lights: [(CGImage, CGFloat)]) {
            drawMusicBackground(r, colors, radius: radius, alpha: alpha, g)
            g.saveGState()
            g.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            g.clip()
            for (image, a) in lights where a > 0.005 {
                g.saveGState()
                g.setAlpha(a * alpha)
                g.interpolationQuality = .none
                g.translateBy(x: r.minX, y: r.maxY)
                g.scaleBy(x: 1, y: -1)
                g.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                g.restoreGState()
            }
            let stops = [glow.cg.copy(alpha: strength) ?? glow.cg, glow.cg.copy(alpha: 0) ?? glow.cg] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops, locations: [0, 1]) {
                g.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: reach, options: [])
            }
            let veil: CGFloat = colors.text.luminance > 0.5 ? (L.card ? 0.12 : 0.2) : 0
            if veil > 0 {
                fillVertical(r, CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: veil), g)
            }
            g.restoreGState()
        }
        /// El fondo completo en una imagen aparte (las capas se juntan antes de recortarlas por
        /// las esquinas de la zona, igual con o sin guardarlo).
        func render(_ colors: MusicCardColors, _ glow: RGB, _ lights: [(CGImage, CGFloat)]) -> CGImage? {
            let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            guard let off = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
            off.clear(CGRect(x: 0, y: 0, width: w, height: h))
            // Misma orientación que la imagen de la moto (origen arriba a la izquierda).
            off.translateBy(x: 0, y: CGFloat(h))
            off.scaleBy(x: 1, y: -1)
            off.translateBy(x: -r.minX, y: -r.minY)
            paint(off, colors, glow, lights)
            return off.makeImage()
        }
        func blit(_ image: CGImage, _ a: CGFloat) {
            ctx.saveGState()
            ctx.setAlpha(a)
            ctx.translateBy(x: r.minX, y: r.minY + CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
        }
        let lightNow = light(s.music.available ? s.music.artwork : nil)
        guard HUDRenderer.cacheStageBackground else {
            // Sin guardar (pruebas): se dibuja entero en cada fotograma, con los colores ya
            // mezclados del cambio de canción.
            var lights: [(CGImage, CGFloat)] = []
            if fadeIn < 1, let old = light(s.musicFrom?.artwork) { lights.append((old.image, lightAlpha * (1 - fadeIn))) }
            if let now = lightNow { lights.append((now.image, lightAlpha * (fadeIn < 1 ? fadeIn : 1))) }
            if let image = render(c, glowColor(s.music.palette, c), lights) {
                blit(image, 1)
            } else {
                paint(ctx, c, glowColor(s.music.palette, c), lights)
            }
            return
        }
        func rgb(_ x: RGB) -> String { String(format: "%.3f,%.3f,%.3f", x.r, x.g, x.b) }
        /// Fondo guardado para unos colores y una luz (lo dibuja si no lo tiene).
        func backdrop(_ colors: MusicCardColors, _ glow: RGB, _ lit: (image: CGImage, signature: String)?) -> CGImage? {
            let key = [String(format: "%.0f,%.0f,%d,%d,%.0f,%.0f,%.0f,%.2f,%.3f", r.minX, r.minY, w, h, center.x, center.y, reach, alpha, lightAlpha),
                       L.style.rawValue, rgb(colors.top), rgb(colors.bottom), rgb(colors.text), rgb(glow), s.night ? "n" : "d",
                       lit?.signature ?? "-"].joined(separator: "|")
            if let i = stageBackgrounds.firstIndex(where: { $0.key == key }) {
                let hit = stageBackgrounds.remove(at: i)
                stageBackgrounds.insert(hit, at: 0)
                return hit.image
            }
            guard let image = render(colors, glow, lit.map { [($0.image, lightAlpha)] } ?? []) else { return nil }
            stageBackgrounds.insert((key, image), at: 0)
            if stageBackgrounds.count > 3 { stageBackgrounds.removeLast() }
            return image
        }
        let spotify = s.music.source == "Spotify"
        let target = MusicCardColors.make(style: s.musicStyle, palette: s.music.palette, night: s.night, intensity: s.musicIntensity, spotify: spotify)
        guard let now = backdrop(target, glowColor(s.music.palette, target), lightNow) else {
            paint(ctx, c, glowColor(s.music.palette, c), lightNow.map { [($0.image, lightAlpha)] } ?? [])
            return
        }
        if fadeIn < 1 {
            // Cambio de canción: el fondo anterior debajo y el nuevo apareciendo encima.
            let before = MusicCardColors.make(style: s.musicStyle, palette: s.paletteFrom, night: s.night, intensity: s.musicIntensity, spotify: spotify)
            if let old = backdrop(before, glowColor(s.paletteFrom, before), light(s.musicFrom?.artwork)) {
                blit(old, 1)
                blit(now, fadeIn)
                return
            }
        }
        blit(now, 1)
    }

    /// 0.6.4: la luz de la portada ya ampliada al tamaño del reproductor (se amplía una vez por
    /// canción; luego solo se copia).
    func ambientScaled(_ art: CGImage, night: Bool, width w: Int, height h: Int) -> (image: CGImage, signature: String)? {
        guard let small = ambientLight(art, night: night) else { return nil }
        if let e = ambientScaledCache.first(where: { $0.art === art && $0.night == night && $0.w == w && $0.h == h }) {
            return (e.image, small.signature)
        }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard w > 0, h > 0, let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        g.interpolationQuality = .high
        g.draw(small.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = g.makeImage() else { return nil }
        ambientScaledCache.insert((art, night, w, h, image), at: 0)
        if ambientScaledCache.count > 3 { ambientScaledCache.removeLast() }
        return (image, small.signature)
    }

    /// 0.6.4: la luz de la portada para el fondo, como en CarPlay: la portada reducida a 4×4
    /// colores (más oscuros de noche y más claros de día, para que el texto se siga leyendo) y
    /// ampliada con suavizado. Se calcula una vez por portada y tema. `signature`: sus colores.
    func ambientLight(_ art: CGImage, night: Bool) -> (image: CGImage, signature: String)? {
        if let a = ambientCache.first(where: { $0.art === art && $0.night == night }) { return (a.image, a.signature) }
        let src = 32
        let n = 4
        let cell = src / n
        var px = [UInt8](repeating: 0, count: src * src * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { raw in
            guard let g = CGContext(data: raw.baseAddress, width: src, height: src, bitsPerComponent: 8, bytesPerRow: src * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            g.interpolationQuality = .high
            g.draw(art, in: CGRect(x: 0, y: 0, width: src, height: src))
            return true
        }
        guard drawn else { return nil }
        var out = [UInt8](repeating: 255, count: n * n * 4)
        var signature = ""
        for by in 0..<n {
            for bx in 0..<n {
                var r = 0.0
                var g = 0.0
                var b = 0.0
                var count = 0.0
                for y in by * cell ..< (by + 1) * cell {
                    for x in bx * cell ..< (bx + 1) * cell {
                        let o = (y * src + x) * 4
                        let a = Double(px[o + 3]) / 255
                        guard a > 0.05 else { continue }
                        r += Double(px[o]) / 255 / a
                        g += Double(px[o + 1]) / 255 / a
                        b += Double(px[o + 2]) / 255 / a
                        count += 1
                    }
                }
                var color = count > 0 ? RGB(min(1, r / count), min(1, g / count), min(1, b / count)) : RGB(0.3, 0.3, 0.3)
                let hsl = color.hsl
                color = night ? RGB(h: hsl.h, s: min(0.7, hsl.s), l: max(0.07, min(0.27, hsl.l * 0.55)))
                              : RGB(h: hsl.h, s: min(0.5, hsl.s * 0.9), l: max(0.74, min(0.9, 0.62 + hsl.l * 0.28)))
                let o = (by * n + bx) * 4
                out[o] = UInt8(max(0, min(255, (color.r * 255).rounded())))
                out[o + 1] = UInt8(max(0, min(255, (color.g * 255).rounded())))
                out[o + 2] = UInt8(max(0, min(255, (color.b * 255).rounded())))
                signature += String(format: "%02x%02x%02x", out[o], out[o + 1], out[o + 2])
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let tiny = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        // Ampliada una vez a 48×48 con buena interpolación: al estirarla queda lisa.
        let side = 48
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let big = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        big.interpolationQuality = .high
        big.draw(tiny, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = big.makeImage() else { return nil }
        ambientCache.insert((art, night, image, signature), at: 0)
        if ambientCache.count > 4 { ambientCache.removeLast() }
        return (image, signature)
    }

    /// 0.6.4: sombra difuminada de la portada (da profundidad, como en la referencia). Se dibuja
    /// una vez por tamaño y tema y luego solo se copia.
    func artShadowImage(_ side: CGFloat, night: Bool) -> (image: CGImage, margin: CGFloat)? {
        let u = max(0.35, min(1, side / 200))
        let blur = 20 * k * u
        let m = (blur * 2.2).rounded(.up)
        let key = String(format: "%.1f|%.2f|%d", side, k, night ? 1 : 0)
        if let image = shadowImages[key] { return (image, m) }
        let w = Int((side + 2 * m).rounded(.up))
        guard w > 0, w < 1400 else { return nil }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let off = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        off.clear(CGRect(x: 0, y: 0, width: w, height: w))
        let rad = (side < 110 ? 4 : 8) * k
        // La forma va fuera de la imagen y solo su sombra cae dentro.
        let far = CGFloat(4 * w)
        off.setShadow(offset: CGSize(width: far, height: 0), blur: blur, color: CGColor(gray: 0, alpha: night ? 0.6 : 0.3))
        off.addPath(CGPath(roundedRect: CGRect(x: m - far, y: m, width: side, height: side), cornerWidth: rad, cornerHeight: rad, transform: nil))
        off.setFillColor(CGColor(gray: 0, alpha: 1))
        off.fillPath()
        guard let image = off.makeImage() else { return nil }
        if shadowImages.count > 16 { shadowImages.removeAll() }
        shadowImages[key] = image
        return (image, m)
    }

    /// Sombra de la portada: la difuminada (0.6.4) o, si no se pudo preparar, tres capas suaves.
    func drawArtShadow(_ art: CGRect, night: Bool, _ ctx: CGContext) {
        let u = max(0.35, min(1, art.width / 200))
        if let shadow = artShadowImage(art.width, night: night) {
            let size = CGFloat(shadow.image.width)
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.draw(shadow.image, in: CGRect(x: art.minX - shadow.margin, y: art.minY - shadow.margin + 7 * k * u, width: size, height: size))
            ctx.restoreGState()
            return
        }
        let base: CGFloat = art.width < 110 ? 4 : 8
        for i in 1...3 {
            let d = CGFloat(i)
            fillRounded(art.offsetBy(dx: 0, dy: (2 + d * 2) * k * u).insetBy(dx: -d * 1.5 * k * u, dy: -d * 1.5 * k * u),
                        radius: (base + d * 2 * u) * k, color: CGColor(gray: 0, alpha: night ? 0.12 : 0.06), ctx)
        }
    }

    /// Un bloque de texto del reproductor: líneas ya medidas y espacio antes de ellas.
    struct PlayerBlock {
        var lines: [Measured]
        var gap: CGFloat
        /// Primera línea de las filas: punto del color de la barra y nombre del servicio.
        var sourceLine = false
    }

    /// Separación entre las líneas de un mismo texto.
    func playerLineGap(_ L: MusicPlayerLayout) -> CGFloat { (L.style == .row ? 1 : 2) * k }

    /// Alto total de unos bloques (como se dibujan en `playerTrack`).
    func playerHeight(_ blocks: [PlayerBlock], _ L: MusicPlayerLayout) -> CGFloat {
        var h: CGFloat = 0
        for (i, b) in blocks.enumerated() {
            if i > 0 { h += b.gap }
            for (j, line) in b.lines.enumerated() {
                h += line.ascent + line.descent
                if j < b.lines.count - 1 { h += playerLineGap(L) }
            }
        }
        return h
    }

    /// Los textos de una canción para una forma del reproductor, ya ajustados al alto disponible:
    /// si no caben, el título pasa a una línea, se quita el álbum y se reduce la letra (hasta
    /// dos veces). Nunca se cortan por el borde: como mucho, el final de una línea lleva "…".
    /// 0.6.4: sin el estado («Reproduciendo»): ahora lo muestra el botón central.
    func playerBlocks(_ m: MusicSnapshot, _ s: DashSnapshot, _ c: MusicCardColors, _ L: MusicPlayerLayout) -> (blocks: [PlayerBlock], height: CGFloat) {
        let has = m.available && !m.title.isEmpty
        let w = L.text.width
        let row = L.style == .row
        func build(scale: CGFloat, twoLines: Bool, album: Bool, artist: Bool) -> [PlayerBlock] {
            if !has {
                let a = textLines("Sin música", sizes: [L.title * 0.9 * scale], bold: true, color: c.secondary.cg, width: w, maxLines: 1)
                let b = textLines("Reproduce algo en el iPhone", sizes: [L.artist * 0.9 * scale, L.artist * 0.8 * scale], bold: false,
                                  color: c.secondary.cg, width: w, maxLines: 2)
                return [PlayerBlock(lines: a.lines, gap: 0), PlayerBlock(lines: b.lines, gap: (row ? 3 : 8) * k)]
            }
            var blocks: [PlayerBlock] = []
            if row && s.showSource && !L.sourceInControls {
                let size = L.source * scale
                let src = textLines(sourceName(m), sizes: [size], bold: true, color: sourceColor(m, c),
                                    width: max(10, w - size * 1.1), maxLines: 1)
                blocks.append(PlayerBlock(lines: src.lines, gap: 0, sourceLine: true))
            }
            let t = L.title * scale
            var title = textLines(m.title, sizes: [t, t * 0.92, t * 0.85], bold: true, color: c.text.cg, width: w, maxLines: 1)
            if !title.fits && twoLines {
                title = textLines(m.title, sizes: [t * 0.9, t * 0.82, t * 0.76], bold: true, color: c.text.cg, width: w, maxLines: 2)
            }
            blocks.append(PlayerBlock(lines: title.lines, gap: (row ? 1.5 : 2) * k))
            if artist && s.showArtist && !m.artist.isEmpty {
                let a = L.artist * scale
                blocks.append(PlayerBlock(lines: textLines(m.artist, sizes: [a, a * 0.9], bold: false, color: c.text.cg, width: w, maxLines: 1).lines,
                                          gap: (L.style == .stage ? 10 : (row ? 1 : 8)) * k))
            }
            if album && L.album > 0 && s.showArtist && !m.album.isEmpty {
                let a = L.album * scale
                blocks.append(PlayerBlock(lines: textLines(m.album, sizes: [a, a * 0.9], bold: false, color: c.secondary.cg, width: w, maxLines: 1).lines,
                                          gap: (row ? 1.5 : 6) * k))
            }
            return blocks
        }
        // De lo más completo a lo más justo.
        var options: [(CGFloat, Bool, Bool, Bool)] = []
        for scale in [1, 0.9, 0.82] as [CGFloat] {
            options.append((scale, true, true, true))
            options.append((scale, false, true, true))
            options.append((scale, false, false, true))
        }
        // Último recurso antes de cortar: el título en dos líneas sin el artista.
        options.append((0.9, true, false, false))
        options.append((0.82, true, false, false))
        options.append((0.82, false, false, false))
        // 0.6.3: antes de cortar un texto con «…» se prueba con letra algo más pequeña (como
        // mucho un 30 % menos); solo si ni así cabe, se corta.
        var last: [PlayerBlock] = []
        var firstFit: ([PlayerBlock], CGFloat)?
        for o in options {
            let b = build(scale: o.0, twoLines: o.1, album: o.2, artist: o.3)
            last = b
            let h = playerHeight(b, L)
            guard h <= L.text.height + 0.5 else { continue }
            if !b.contains(where: { $0.lines.contains { $0.truncated } }) { return (b, h) }
            if firstFit == nil { firstFit = (b, h) }
        }
        if let f = firstFit { return f }
        return (last, playerHeight(last, L))
    }

    /// Portada y textos de una canción (con transparencia y desplazamiento para la transición),
    /// en cualquiera de las tres formas.
    func playerTrack(_ m: MusicSnapshot, _ s: DashSnapshot, _ c: MusicCardColors, _ L: MusicPlayerLayout, _ p: HUDPalette,
                     artAlpha: CGFloat, textAlpha: CGFloat, dy: CGFloat, art: CGImage?, artFrom: CGImage?, artFade: CGFloat,
                     _ ctx: CGContext) {
        let has = m.available && !m.title.isEmpty
        if L.artwork.width > 4 && artAlpha > 0.01 {
            let behind = c.top.mixed(with: c.bottom, 0.5).cg
            ctx.saveGState()
            ctx.setAlpha(artAlpha)
            drawArtShadow(L.artwork, night: s.night, ctx)
            if artFade < 1 {
                dashArtwork(has ? artFrom : nil, L.artwork, p, ctx, fill: behind)
                ctx.setAlpha(artAlpha * max(0, artFade))
            }
            dashArtwork(has ? art : nil, L.artwork, p, ctx, fill: behind)
            ctx.restoreGState()
            // 0.6.4: un filo muy fino alrededor (fuera de la portada) la separa de un fondo del
            // mismo color.
            let radius = (L.artwork.width < 110 ? 4 : 8) * k
            ctx.saveGState()
            ctx.setAlpha(artAlpha)
            ctx.addPath(CGPath(roundedRect: L.artwork.insetBy(dx: -0.75 * k, dy: -0.75 * k), cornerWidth: radius + 0.75 * k,
                               cornerHeight: radius + 0.75 * k, transform: nil))
            ctx.setStrokeColor(c.text.cg.copy(alpha: c.text.luminance > 0.5 ? 0.14 : 0.1) ?? c.text.cg)
            ctx.setLineWidth(1 * k)
            ctx.strokePath()
            ctx.restoreGState()
        }
        guard textAlpha > 0.01, L.text.width > 30 * k, L.text.height > 10 * k else { return }
        ctx.saveGState()
        ctx.setAlpha(textAlpha)
        let fit = playerBlocks(m, s, c, L)
        let lineGap = playerLineGap(L)
        // Centrados en el alto disponible; si no cupieran, nunca por encima del borde de arriba.
        var y = max(L.text.minY, L.text.midY - fit.height / 2) + dy
        for (i, b) in fit.blocks.enumerated() {
            if i > 0 { y += b.gap }
            for (j, line) in b.lines.enumerated() {
                var x = L.centered ? L.text.midX - line.width / 2 : L.text.minX
                if b.sourceLine {
                    // Punto del color de la barra delante del nombre del servicio.
                    let h = line.ascent + line.descent
                    let d = h * 0.5
                    ctx.setFillColor(c.accent.cg)
                    ctx.fillEllipse(in: CGRect(x: x, y: y + (h - d) / 2, width: d, height: d))
                    x += d * 1.7
                }
                put(line, x: x, baseline: y + line.ascent, ctx)
                y += line.ascent + line.descent
                if j < b.lines.count - 1 { y += lineGap }
            }
        }
        ctx.restoreGState()
    }

    // MARK: - Avisos

    /// Zona de avisos (0.6.3): cabecera con la campana, tarjetas de vidrio con el icono de quién
    /// lo envía, el título, el mensaje y cuánto hace; sin avisos, un estado vacío centrado (antes
    /// quedaba casi toda la zona en blanco).
    func dashNotices(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let pad = max(9 * k, min(14 * k, min(r.width, r.height) * 0.05))
        let hs = 14 * k
        let bell = CGRect(x: r.minX + pad, y: r.minY + pad + 1 * k, width: hs, height: hs)
        bellGlyph(bell, p.dim, ctx)
        let head = measure("Avisos", size: hs, bold: true, color: p.dim)
        put(head, x: bell.maxX + 6 * k, baseline: bell.midY + (head.ascent - head.descent) / 2, ctx)
        if !s.notices.isEmpty {
            let count = measure("\(s.notices.count)", size: 11 * k, bold: true, color: p.text)
            let badge = CGRect(x: bell.maxX + 6 * k + head.width + 7 * k, y: bell.midY - 9 * k, width: max(18 * k, count.width + 10 * k), height: 18 * k)
            fillRounded(badge, radius: 9 * k, color: p.accent.copy(alpha: 0.85) ?? p.accent, ctx)
            put(count, x: badge.midX - count.width / 2, baseline: badge.midY + (count.ascent - count.descent) / 2, ctx)
        }
        let y0 = bell.maxY + 10 * k
        let avail = r.maxY - pad - y0
        guard avail > 24 * k else { return }
        if s.notices.isEmpty {
            // Estado vacío centrado.
            let d = min(52 * k, avail * 0.36)
            let mid = y0 + avail * 0.42
            let circle = CGRect(x: r.midX - d / 2, y: mid - d, width: d, height: d)
            glassCard(circle, radius: d / 2, p, ctx, shadow: false)
            bellGlyph(circle.insetBy(dx: d * 0.27, dy: d * 0.27), p.dim, ctx)
            let w = r.width - 2 * pad
            let y = paragraph("Sin avisos", sizes: [17 * k, 15 * k], bold: true, color: p.dim, x: r.minX + pad, top: mid + 10 * k,
                              width: w, maxLines: 1, ctx, align: 0.5)
            if r.maxY - pad - y > 30 * k {
                paragraph("Aquí aparecen los avisos de la ruta, la moto y el iPhone", sizes: [12.5 * k, 11.5 * k], bold: false,
                          color: p.faint, x: r.minX + pad, top: y + 5 * k, width: w, maxLines: 2, ctx, align: 0.5)
            }
            return
        }
        let gap = 7 * k
        let ch = max(46 * k, min(66 * k, (avail - gap) / 2))
        let count = max(1, Int((avail + gap) / (ch + gap)))
        var y = y0
        for note in s.notices.sorted(by: { $0.time > $1.time }).prefix(count) {
            let card = CGRect(x: r.minX + pad, y: y, width: r.width - 2 * pad, height: min(ch, r.maxY - pad - y))
            glassCard(card, radius: 12 * k, p, ctx, shadow: false)
            let side = min(card.height - 16 * k, 38 * k)
            let ic = CGRect(x: card.minX + 10 * k, y: card.midY - side / 2, width: side, height: side)
            dashNoticeIcon(note.kind, ic, p, ctx)
            let tx = ic.maxX + 10 * k
            let tw = card.maxX - 10 * k - tx
            let age = measure(noticeAge(note, now), size: 11 * k, bold: false, color: p.dim)
            // Remitente y hora arriba, título en negrita y mensaje debajo (con alto suficiente);
            // si la tarjeta es baja, título y mensaje.
            let tall = card.height >= 60 * k
            var top = card.midY - (tall ? 25 : 17.5) * k
            if tall {
                textLine(noticeSender(note.kind), sizes: [10 * k], bold: true, color: p.faint, x: tx, top: top, width: tw - age.width - 8 * k, ctx)
                put(age, x: card.maxX - 10 * k - age.width, baseline: top + age.ascent, ctx)
                top += 14 * k
            } else {
                put(age, x: card.maxX - 10 * k - age.width, baseline: top + 1 * k + age.ascent, ctx)
            }
            wrapped(note.title, sizes: [15 * k, 14 * k, 13 * k], color: p.text, x: tx, top: top, width: tw - (tall ? 0 : age.width + 8 * k), maxLines: 1, ctx)
            textLine(s.privacy ? "Contenido oculto" : note.text, sizes: [13 * k, 12 * k, 11.5 * k], bold: false, color: p.dim,
                     x: tx, top: top + 19.5 * k, width: tw, ctx)
            y += ch + gap
        }
    }

    /// Icono de cada aviso en su mosaico: navegación (azul), moto (verde, Wi-Fi), batería del
    /// iPhone (ámbar) y prueba (violeta).
    func dashNoticeIcon(_ kind: NoticeKind, _ r: CGRect, _ p: HUDPalette, _ ctx: CGContext) {
        let colors: (CGColor, CGColor)
        switch kind {
        case .nav: colors = tileColors(.blue, p)
        case .link: colors = tileColors(.good, p)
        case .battery: colors = tileColors(.amber, p)
        case .test: colors = tileColors(.violet, p)
        }
        iconTile(r, colors, ctx)
        let g = r.insetBy(dx: r.width * 0.2, dy: r.height * 0.2)
        let white = HUDRenderer.white(1)
        switch kind {
        case .nav: HUDIcons.draw(.straight, in: r.insetBy(dx: r.width * 0.17, dy: r.height * 0.17), color: white, hole: colors.1, ctx: ctx)
        case .link: linkGlyph(g, white, ctx)
        case .battery: batteryGlyph(g, white, ctx)
        case .test: bellGlyph(g, white, ctx)
        }
    }
}

/// Dibuja el panel en una imagen. Lo usan la vista previa del iPhone y las pruebas: es el
/// mismo código que produce la imagen para la moto.
enum DashPreview {
    static func image(_ s: DashSnapshot, width: Int = 800, height: Int = 400, now: Date = Date(), renderer: HUDRenderer? = nil) -> CGImage? {
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        (renderer ?? HUDRenderer(width: width, height: height)).drawDashboard(s, now: now, in: ctx)
        return ctx.makeImage()
    }
}
