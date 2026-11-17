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

        if s.layout.template == .overlay {
            let area = CGRect(x: 0, y: 0, width: width, height: height)
            let streets = drawOverlay(s, p, now, area, ctx)
            if s.mapSettings.streets && !streets && !s.demo { tags.append("MAPA SIMPLE") }
            drawTags(tags, p, top: area.minY + 12 * k, ctx)
            return
        }

        let gap = (6 * k).rounded()
        var area = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: gap, dy: gap)
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
            // Si hay etiquetas arriba a la derecha, la brújula del mapa baja para no quedar tapada.
            let underTags = !tags.isEmpty && f.rect.maxX > area.maxX - 1 && f.rect.minY < area.minY + 1
            compassDrop = underTags ? 26 * k : 0
            let radius = 14 * k
            ctx.addPath(CGPath(roundedRect: f.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
            ctx.setFillColor(p.panel)
            ctx.fill(f.rect)
            switch f.module {
            case .nav: dashNav(s, p, now, f.rect, ctx)
            case .turn: dashTurn(s.nav, p, f.rect, ctx)
            case .map: dashMap(s, p, now, f.rect, ctx)
            case .trip: dashTrip(s.nav, p, now, f.rect, ctx)
            case .music: dashMusic(s, p, now, f.rect, ctx)
            case .notices: dashNotices(s, p, now, f.rect, ctx)
            case .clock: dashClock(p, now, f.rect, ctx)
            }
            ctx.restoreGState()
        }
        compassDrop = 0
        if strip {
            let r = CGRect(x: area.minX, y: area.maxY + gap, width: area.width, height: 62 * k)
            dashTurnStrip(s.nav, p, r, ctx)
        }

        var right = area.maxX - 6 * k
        for tag in tags {
            let m = measure(tag, size: 13 * k, bold: true, color: p.background)
            let pill = CGRect(x: right - m.width - 14 * k, y: area.minY + 6 * k, width: m.width + 14 * k, height: 22 * k)
            fillRounded(pill, radius: 11 * k, color: p.warn, ctx)
            put(m, x: pill.minX + 7 * k, baseline: pill.midY + (m.ascent - m.descent) / 2, ctx)
            right = pill.minX - 6 * k
        }
    }

    /// Etiquetas de estado (DEMO, SIMULACIÓN…) centradas arriba.
    func drawTags(_ tags: [String], _ p: HUDPalette, top: CGFloat, _ ctx: CGContext) {
        guard !tags.isEmpty else { return }
        let ms = tags.map { measure($0, size: 13 * k, bold: true, color: p.background) }
        let total = ms.reduce(0) { $0 + $1.width + 14 * k } + CGFloat(ms.count - 1) * 6 * k
        var x = width / 2 - total / 2
        for m in ms {
            let pill = CGRect(x: x, y: top, width: m.width + 14 * k, height: 22 * k)
            fillRounded(pill, radius: 11 * k, color: p.warn, ctx)
            put(m, x: pill.minX + 7 * k, baseline: pill.midY + (m.ascent - m.descent) / 2, ctx)
            x = pill.maxX + 6 * k
        }
    }

    // MARK: - Mapa completo con tarjetas

    /// Fondo de las tarjetas flotantes: semitransparente, con borde suave.
    func cardBackground(_ r: CGRect, _ p: HUDPalette, _ ctx: CGContext, radius: CGFloat? = nil) {
        let rad = radius ?? 18 * k
        fillRounded(r, radius: rad, color: alpha(p.background, 0.86), ctx)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: rad, cornerHeight: rad, transform: nil))
        ctx.setStrokeColor(alpha(p.text, 0.1))
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Mapa en toda el área y las tarjetas encima. Devuelve true si se dibujó el mapa de calles.
    @discardableResult
    func drawOverlay(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ area: CGRect, _ ctx: CGContext) -> Bool {
        let n = s.nav
        let o = s.layout.overlay
        let cards = DashLayoutEngine.overlayCards(o, in: area, k: k, showNotices: !s.notices.isEmpty)
        let compass = cards.first { $0.item == .compass }?.rect
        var streets = drawStreetMap(s, p, now, area, ctx, compass: compass)
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
            switch card.item {
            case .maneuver:
                if let ext = s.external, !n.navigating {
                    let small = CGRect(x: r.minX, y: r.minY, width: r.width, height: min(r.height, 112 * k))
                    cardBackground(small, p, ctx)
                    dashExternalCard(ext, s, p, now, small, ctx)
                } else if n.navigating || n.arrived {
                    cardBackground(r, p, ctx)
                    dashTurnContent(n, p, r, ctx)
                } else {
                    let small = CGRect(x: r.minX, y: r.minY, width: r.width, height: min(r.height, 92 * k))
                    cardBackground(small, p, ctx)
                    dashTurnContent(n, p, small, ctx)
                }
            case .music:
                if o.musicSize == .large {
                    dashMusic(s, p, now, r, ctx, cardRadius: 18 * k, alpha: 0.94)
                } else {
                    dashMusicCompact(s, p, now, r, ctx)
                }
            case .trip:
                dashTripPill(n, p, now, r, ctx)
            case .notices:
                if let note = s.notices.max(by: { $0.time < $1.time }) {
                    cardBackground(r, p, ctx, radius: 16 * k)
                    dashNoticeCard(note, s.privacy, p, now, r, ctx)
                }
            case .clock:
                dashClockPill(p, now, r, ctx)
            case .compass:
                break
            }
        }
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

    /// Música en una tarjeta pequeña: portada, estado, canción, artista y progreso.
    func dashMusicCompact(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let m = s.music
        let pad = 10 * k
        let has = m.available && !m.title.isEmpty
        let c = musicColors(s)
        drawMusicBackground(r, c, radius: 18 * k, alpha: 0.94, ctx)
        var tx = r.minX + pad
        if s.showArtwork {
            let a = r.height - 2 * pad
            let art = CGRect(x: r.minX + pad, y: r.minY + pad, width: a, height: a)
            dashArtwork(has ? m.artwork : nil, art, p, ctx)
            tx = art.maxX + 12 * k
        }
        let tw = r.maxX - pad - tx
        guard tw > 30 else { return }
        if !has {
            wrapped("Sin música", sizes: [19 * k], color: c.secondary.cg, x: tx, top: r.minY + pad + 4 * k, width: tw, maxLines: 1, ctx)
            wrapped("Reproduce algo en el iPhone", sizes: [14 * k, 12 * k], color: c.secondary.cg, x: tx, top: r.minY + pad + 32 * k, width: tw, maxLines: 2, ctx)
            return
        }
        var line = r.minY + pad
        if s.showSource {
            let state = (m.source.isEmpty ? "MÚSICA" : m.source.uppercased()) + (m.playing ? "  ▶" : "  ❚❚")
            let sm = measure(state, size: 12 * k, bold: true, color: sourceColor(m, c))
            put(sm, x: tx, baseline: line + sm.ascent, ctx)
            line += 16 * k
        } else {
            line += 4 * k
        }
        wrapped(m.title, sizes: [19 * k, 17 * k], color: c.text.cg, x: tx, top: line, width: tw, maxLines: 1, ctx)
        if s.showArtist {
            wrapped(m.artist, sizes: [15 * k, 13 * k], color: c.secondary.cg, x: tx, top: line + 24 * k, width: tw, maxLines: 1, ctx)
        }
        if s.showProgress && m.duration > 1 {
            let elapsed = m.playing ? max(0, now.timeIntervalSinceReferenceDate - m.positionTime) : 0
            let pos = max(0, min(m.duration, m.position + elapsed))
            let bar = CGRect(x: tx, y: r.maxY - pad - 3 * k, width: tw, height: 3 * k)
            fillRounded(bar, radius: 1.5 * k, color: c.track.cg, ctx)
            fillRounded(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(pos / m.duration), height: bar.height), radius: 1.5 * k, color: c.accent.cg, ctx)
        }
    }

    /// Guía en otra app: la tarjeta dice cuál, el destino y la distancia en línea recta.
    func dashExternalCard(_ ext: ExternalGuide, _ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let pad = 10 * k
        let t = r.height - 2 * pad
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: min(t, 64 * k), height: min(t, 64 * k))
        fillRounded(tile, radius: tile.width * 0.22, color: p.accent, ctx)
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
            let tx = tile.maxX + 12 * k
            let tw = r.maxX - pad - tx
            let head = measure("Guía en \(ext.provider.title)", size: 13 * k, bold: true, color: p.accent)
            put(head, x: tx, baseline: r.minY + pad + head.ascent, ctx)
            wrapped(ext.name, sizes: [20 * k, 17 * k, 15 * k], color: p.text, x: tx, top: r.minY + pad + 18 * k, width: tw, maxLines: 1, ctx)
            wrapped("A \(HUDFormat.distance(km)) en línea recta", sizes: [14 * k, 12 * k], color: p.dim, x: tx, top: r.minY + pad + 46 * k, width: tw, maxLines: 1, ctx)
        } else {
            let tx = tile.maxX + 12 * k
            wrapped("Guía en \(ext.provider.title)", sizes: [18 * k, 15 * k], color: p.text, x: tx, top: r.minY + pad, width: r.maxX - pad - tx, maxLines: 1, ctx)
            wrapped(ext.name, sizes: [15 * k, 13 * k], color: p.dim, x: tx, top: r.minY + pad + 26 * k, width: r.maxX - pad - tx, maxLines: 1, ctx)
        }
    }

    /// Barra de viaje: hora de llegada, tiempo y distancia restantes, y el avance.
    func dashTripPill(_ n: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        guard n.navigating && !n.arrived else {
            dashClockPill(p, now, r, ctx)
            return
        }
        let clock = n.eta.map { HUDFormat.clock($0) }
        let text = "\(clock?.time ?? "--:--") \(clock?.suffix ?? "")  ·  \(HUDFormat.durationCompact(n.remainingTime))  ·  \(HUDFormat.distance(n.remainingDistance))"
        var size = 24 * k
        var m = measure(text, size: size, bold: true, color: p.text)
        let maxW = r.width - 36 * k
        if m.width > maxW {
            size *= max(0.6, maxW / m.width)
            m = measure(text, size: size, bold: true, color: p.text)
        }
        let w = min(r.width, m.width + 36 * k)
        let pill = CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height)
        cardBackground(pill, p, ctx, radius: r.height / 2)
        put(m, x: pill.midX - m.width / 2, baseline: pill.midY + (m.ascent - m.descent) / 2 - 1 * k, ctx)
        let f = CGFloat(max(0, min(1, n.fraction)))
        let track = CGRect(x: pill.minX + r.height * 0.45, y: pill.maxY - 6 * k, width: pill.width - r.height * 0.9, height: 3 * k)
        fillRounded(track, radius: 1.5 * k, color: alpha(p.line, 0.9), ctx)
        if f > 0.01 {
            fillRounded(CGRect(x: track.minX, y: track.minY, width: track.width * f, height: track.height), radius: 1.5 * k, color: p.accent, ctx)
        }
    }

    func dashClockPill(_ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let c = HUDFormat.clock(now)
        let t = measure(c.time, size: 24 * k, bold: true, color: p.text)
        let sfx = measure(c.suffix, size: 13 * k, bold: true, color: p.dim)
        let w = min(r.width, t.width + sfx.width + 40 * k)
        let pill = CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height)
        cardBackground(pill, p, ctx, radius: r.height / 2)
        let x = pill.midX - (t.width + 5 * k + sfx.width) / 2
        let base = pill.midY + (t.ascent - t.descent) / 2
        put(t, x: x, baseline: base, ctx)
        put(sfx, x: x + t.width + 5 * k, baseline: base, ctx)
    }

    /// El aviso más reciente como tarjeta flotante.
    func dashNoticeCard(_ note: NoticeSnapshot, _ privacy: Bool, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let pad = 10 * k
        let side = r.height - 2 * pad
        let ic = CGRect(x: r.minX + pad, y: r.minY + pad, width: side, height: side)
        dashNoticeIcon(note.kind, ic, p, ctx)
        let tx = ic.maxX + 10 * k
        let tw = r.maxX - pad - tx
        wrapped(note.title, sizes: [17 * k, 15 * k], color: p.text, x: tx, top: r.minY + pad - 1 * k, width: tw, maxLines: 1, ctx)
        wrapped(privacy ? "Contenido oculto" : note.text, sizes: [14 * k, 12 * k], color: p.dim, x: tx, top: r.minY + pad + 20 * k, width: tw, maxLines: 1, ctx)
    }

    /// Franja con el próximo giro para los diseños sin mapa (por ejemplo, el de música).
    func dashTurnStrip(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        fillRounded(r, radius: 14 * k, color: p.panel, ctx)
        let t = r.height - 14 * k
        let tile = CGRect(x: r.minX + 7 * k, y: r.minY + 7 * k, width: t, height: t)
        let color = n.rerouting ? p.warn : p.accent
        fillRounded(tile, radius: t * 0.22, color: color, ctx)
        HUDIcons.draw(n.kind, in: tile.insetBy(dx: t * 0.14, dy: t * 0.14), color: p.onAccent, hole: color, ctx: ctx)
        let parts = HUDFormat.distanceParts(n.distanceToManeuver)
        let big = measure(parts.value, size: 32 * k, bold: true, color: p.text)
        let unit = measure(parts.unit, size: 16 * k, bold: true, color: p.dim)
        let x = tile.maxX + 12 * k
        let base = r.midY + (big.ascent - big.descent) / 2
        put(big, x: x, baseline: base, ctx)
        put(unit, x: x + big.width + 4 * k, baseline: base, ctx)
        let lx = x + big.width + unit.width + 18 * k
        let line = n.rerouting ? "Recalculando la ruta…" : n.instruction
        wrapped(line, sizes: [20 * k, 17 * k, 15 * k], color: n.rerouting ? p.warn : p.text, x: lx, top: r.midY - 12 * k, width: r.maxX - 12 * k - lx, maxLines: 1, ctx)
    }

    // MARK: - Navegación

    func dashMap(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext, anchorX: CGFloat = 0.5) {
        let size = 40 * k
        let compass = CGRect(x: r.maxX - size - 10 * k, y: r.minY + 10 * k + compassDrop, width: size, height: size)
        if drawStreetMap(s, p, now, r, ctx, compass: compass) { return }
        let u = max(0.5, min(r.width, r.height) / 400)
        let anchor = CGPoint(x: r.minX + r.width * anchorX, y: r.maxY - r.height * 0.24)
        drawMiniMap(s.nav, p, now, r, ctx, anchor: anchor, unit: u, divider: false)
    }

    func dashNav(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let n = s.nav
        let wide = r.width > r.height * 1.25
        dashMap(s, p, now, r, ctx, anchorX: wide ? 0.74 : 0.5)
        let pad = (r.height * 0.03).rounded() + 2
        let card: CGRect
        if wide {
            card = CGRect(x: r.minX + pad, y: r.minY + pad, width: min(r.width * 0.5, r.height * 1.25), height: r.height * 0.62)
        } else {
            card = CGRect(x: r.minX + pad, y: r.minY + pad, width: r.width - 2 * pad, height: r.height * 0.46)
        }
        if let ext = s.external, !n.navigating {
            let small = CGRect(x: card.minX, y: card.minY, width: card.width, height: min(card.height, 112 * k))
            fillRounded(small, radius: small.height * 0.14, color: alpha(p.background, 0.93), ctx)
            dashExternalCard(ext, s, p, now, small, ctx)
            return
        }
        fillRounded(card, radius: card.height * 0.1, color: alpha(p.background, 0.93), ctx)
        dashTurnContent(n, p, card, ctx)

        if n.navigating && !n.arrived {
            let clock = n.eta.map { HUDFormat.clock($0) }
            let text = "\(clock?.time ?? "--:--") \(clock?.suffix ?? "")  ·  \(HUDFormat.durationCompact(n.remainingTime))  ·  \(HUDFormat.distance(n.remainingDistance))"
            let size = max(11, r.height * 0.062)
            let m = measure(text, size: size, bold: true, color: p.text)
            let h = size * 1.9
            let pill = CGRect(x: r.minX + pad, y: r.maxY - pad - h, width: min(m.width + size * 1.4, r.width - 2 * pad), height: h)
            fillRounded(pill, radius: h / 2, color: alpha(p.background, 0.93), ctx)
            put(m, x: pill.minX + size * 0.7, baseline: pill.midY + (m.ascent - m.descent) / 2, ctx)
        }
    }

    func dashTurn(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        dashTurnContent(n, p, r, ctx)
    }

    /// Flecha, distancia e instrucción dentro de un rectángulo cualquiera.
    func dashTurnContent(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        let pad = max(6, min(r.width, r.height) * 0.07)
        let t = min(r.height * 0.5, r.width * 0.3)
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
        let textX = tile.maxX + pad * 0.9
        let textW = r.maxX - pad - textX

        var color = p.accent
        var kind = n.kind
        var big = ""
        var unit = ""
        var line = n.instruction
        var lineColor = p.text
        var iconColor = p.onAccent
        if n.arrived {
            color = p.good
            kind = .arrive
            big = "Llegaste"
            line = n.destinationName
        } else if !n.navigating {
            color = p.line
            kind = .depart
            big = "Sin ruta"
            line = "Elige un destino en el iPhone"
            lineColor = p.dim
            iconColor = p.dim
        } else {
            let parts = HUDFormat.distanceParts(n.distanceToManeuver)
            big = parts.value
            unit = parts.unit
            if n.rerouting {
                color = p.warn
                line = "Recalculando la ruta…"
                lineColor = p.warn
            }
        }
        fillRounded(tile, radius: t * 0.22, color: color, ctx)
        HUDIcons.draw(kind, in: tile.insetBy(dx: t * 0.12, dy: t * 0.12), color: iconColor, hole: color, ctx: ctx)

        var size = t * (unit.isEmpty ? 0.4 : 0.66)
        var m = measure(big, size: size, bold: true, color: p.text)
        var unitWidth: CGFloat = unit.isEmpty ? 0 : measure(unit, size: size * 0.45, bold: true, color: p.dim).width + size * 0.12
        if m.width + unitWidth > textW, m.width > 0 {
            size *= max(0.45, textW / (m.width + unitWidth))
            m = measure(big, size: size, bold: true, color: p.text)
            unitWidth = unit.isEmpty ? 0 : measure(unit, size: size * 0.45, bold: true, color: p.dim).width + size * 0.12
        }
        let showThen = n.thenKind != nil && n.navigating && !n.rerouting && !n.arrived
        let baseline = showThen ? tile.minY + m.ascent * 0.92 : tile.midY + (m.ascent - m.descent) / 2
        put(m, x: textX, baseline: baseline, ctx)
        if !unit.isEmpty {
            let um = measure(unit, size: size * 0.45, bold: true, color: p.dim)
            put(um, x: textX + m.width + size * 0.12, baseline: baseline, ctx)
        }
        if showThen, let then = n.thenKind {
            let ls = t * 0.2
            let lm = measure("Luego", size: ls, bold: false, color: p.dim)
            let y = tile.maxY - ls * 1.6
            put(lm, x: textX, baseline: y + lm.ascent, ctx)
            HUDIcons.draw(
                then, in: CGRect(x: textX + lm.width + ls * 0.4, y: y - ls * 0.3, width: ls * 1.8, height: ls * 1.8),
                color: p.text, hole: p.background, ctx: ctx
            )
        }

        let top = tile.maxY + pad * 0.6
        let avail = r.maxY - pad * 0.6 - top
        if avail > 12 {
            let s1 = min(t * 0.36, avail / 2.45)
            wrapped(line, sizes: [s1, s1 * 0.9, s1 * 0.8], color: lineColor, x: r.minX + pad, top: top, width: r.width - 2 * pad, maxLines: 2, ctx)
        }
    }

    func dashTrip(_ n: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        guard n.navigating && !n.arrived else {
            dashClock(p, now, r, ctx)
            return
        }
        let pad = max(8, min(r.width, r.height) * 0.09)
        let clock = n.eta.map { HUDFormat.clock($0) }
        let items: [(String, String)] = [
            (clock?.time ?? "--:--", "llegada " + (clock?.suffix ?? "")),
            (HUDFormat.durationCompact(n.remainingTime), "restante"),
            (HUDFormat.distance(n.remainingDistance), "distancia"),
        ]
        let barH = max(3, r.height * 0.035)
        let inner = CGRect(x: r.minX + pad, y: r.minY + pad, width: r.width - 2 * pad, height: r.height - 2 * pad - barH - pad * 0.5)
        if inner.width >= 300 {
            let cw = inner.width / 3
            let vs = min(inner.height * 0.42, cw * 0.3)
            for (i, item) in items.enumerated() {
                let v = measure(item.0, size: vs, bold: true, color: p.text)
                let l = measure(item.1, size: vs * 0.5, bold: false, color: p.dim)
                let x = inner.minX + cw * CGFloat(i)
                let y = inner.midY - (vs + vs * 0.75) / 2
                put(v, x: x, baseline: y + v.ascent, ctx)
                put(l, x: x, baseline: y + vs * 1.2 + l.ascent, ctx)
            }
        } else {
            let rh = inner.height / 3
            let vs = min(rh * 0.62, inner.width * 0.17)
            for (i, item) in items.enumerated() {
                let v = measure(item.0, size: vs, bold: true, color: p.text)
                let l = measure(item.1, size: vs * 0.55, bold: false, color: p.dim)
                let mid = inner.minY + rh * (CGFloat(i) + 0.5)
                put(v, x: inner.minX, baseline: mid + (v.ascent - v.descent) / 2, ctx)
                put(l, x: inner.maxX - l.width, baseline: mid + (l.ascent - l.descent) / 2, ctx)
            }
        }
        let track = CGRect(x: r.minX + pad, y: r.maxY - pad - barH, width: r.width - 2 * pad, height: barH)
        fillRounded(track, radius: barH / 2, color: p.line, ctx)
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

    // MARK: - Música

    func dashMusic(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext,
                   cardRadius: CGFloat = 0, alpha: CGFloat = 1) {
        let m = s.music
        let c = musicColors(s)
        drawMusicBackground(r, c, radius: cardRadius, alpha: alpha, ctx)
        let pad = max(8, min(r.width, r.height) * 0.08)
        let has = m.available && !m.title.isEmpty
        let vertical = r.height >= 190 && r.height > r.width * 0.9
        let fraction = s.artworkSize.fraction
        var art = CGRect.zero
        if s.showArtwork {
            if vertical {
                let a = min(r.width - 2 * pad, r.height * 0.48 * fraction)
                art = CGRect(x: r.midX - a / 2, y: r.minY + pad, width: a, height: a)
            } else {
                let a = min((r.height - 2 * pad) * fraction, r.width * 0.4)
                art = CGRect(x: r.minX + pad, y: r.midY - a / 2, width: a, height: a)
            }
            dashArtwork(has ? m.artwork : nil, art, p, ctx)
        }
        let tx = (s.showArtwork && !vertical) ? art.maxX + pad : r.minX + pad
        let top = (s.showArtwork && vertical) ? art.maxY + pad * 0.7 : r.minY + pad
        let tw = r.maxX - pad - tx
        let th = r.maxY - pad - top
        guard tw > 40, th > 20 else { return }
        let base = max(11, min(th * 0.2, tw * 0.12, 34 * k))

        if !has {
            wrapped("Sin música", sizes: [base], color: c.secondary.cg, x: tx, top: top + th * 0.2, width: tw, maxLines: 1, ctx)
            wrapped("Reproduce algo en el iPhone", sizes: [base * 0.7, base * 0.6], color: c.secondary.cg, x: tx, top: top + th * 0.2 + base * 1.4, width: tw, maxLines: 2, ctx)
            return
        }

        // Estado (reproduciendo o en pausa) y origen.
        let icon = base * 0.62
        ctx.setFillColor(sourceColor(m, c))
        if m.playing {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: tx, y: top))
            ctx.addLine(to: CGPoint(x: tx + icon * 0.9, y: top + icon / 2))
            ctx.addLine(to: CGPoint(x: tx, y: top + icon))
            ctx.closePath()
            ctx.fillPath()
        } else {
            ctx.fill(CGRect(x: tx, y: top, width: icon * 0.3, height: icon))
            ctx.fill(CGRect(x: tx + icon * 0.5, y: top, width: icon * 0.3, height: icon))
        }
        if s.showSource {
            let src = measure(m.source.uppercased(), size: icon * 0.95, bold: true, color: sourceColor(m, c))
            put(src, x: tx + icon * 1.3, baseline: top + icon * 0.5 + (src.ascent - src.descent) / 2, ctx)
        }

        let titleTop = top + icon * 1.7
        wrapped(m.title, sizes: [base, base * 0.88], color: c.text.cg, x: tx, top: titleTop, width: tw, maxLines: 1, ctx)
        if s.showArtist {
            wrapped(m.artist, sizes: [base * 0.78], color: c.secondary.cg, x: tx, top: titleTop + base * 1.3, width: tw, maxLines: 1, ctx)
        }

        if s.showProgress && m.duration > 1 {
            let elapsed = m.playing ? max(0, now.timeIntervalSinceReferenceDate - m.positionTime) : 0
            let pos = max(0, min(m.duration, m.position + elapsed))
            let barH = max(3, base * 0.2)
            let bar = CGRect(x: tx, y: r.maxY - pad - barH, width: tw, height: barH)
            fillRounded(bar, radius: barH / 2, color: c.track.cg, ctx)
            fillRounded(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(pos / m.duration), height: barH), radius: barH / 2, color: c.accent.cg, ctx)
            let ts = base * 0.58
            if bar.minY - ts * 1.5 > titleTop + base * 2.3 {
                let a = measure(dashTime(pos), size: ts, bold: false, color: c.secondary.cg)
                let b = measure(dashTime(m.duration), size: ts, bold: false, color: c.secondary.cg)
                put(a, x: bar.minX, baseline: bar.minY - ts * 0.45, ctx)
                put(b, x: bar.maxX - b.width, baseline: bar.minY - ts * 0.45, ctx)
            }
        }
    }

    func dashTime(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    func dashArtwork(_ image: CGImage?, _ rect: CGRect, _ p: HUDPalette, _ ctx: CGContext) {
        guard rect.width > 4 else { return }
        // Reglas de Spotify para portadas: sin recortes ni nada encima y esquinas de 4 px
        // (pequeñas) u 8 px (grandes). Se aplica igual a Apple Music.
        let radius = (rect.width < 110 ? 4 : 8) * k
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        if let image = image {
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
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

    // MARK: - Avisos

    func dashNotices(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let pad = max(7, min(r.width, r.height) * 0.07)
        let hs = max(10, min(r.height * 0.1, 15 * k))
        let head = measure("AVISOS", size: hs, bold: true, color: p.dim)
        put(head, x: r.minX + pad, baseline: r.minY + pad + head.ascent, ctx)
        var y = r.minY + pad + hs * 1.6
        let avail = r.maxY - pad - y
        guard avail > 24 else { return }
        if s.notices.isEmpty {
            wrapped("Sin avisos", sizes: [hs * 1.3], color: p.dim, x: r.minX + pad, top: y + avail * 0.2, width: r.width - 2 * pad, maxLines: 1, ctx)
            return
        }
        let gap: CGFloat = 4
        let ch = min(max((avail - gap) / 2, 30), 60)
        let count = max(1, Int((avail + gap) / (ch + gap)))
        let t = now.timeIntervalSinceReferenceDate
        for note in s.notices.sorted(by: { $0.time > $1.time }).prefix(count) {
            let card = CGRect(x: r.minX + pad, y: y, width: r.width - 2 * pad, height: min(ch, r.maxY - pad - y))
            fillRounded(card, radius: ch * 0.22, color: alpha(p.background, 0.75), ctx)
            let side = ch * 0.7
            let ic = CGRect(x: card.minX + ch * 0.15, y: card.midY - side / 2, width: side, height: side)
            dashNoticeIcon(note.kind, ic, p, ctx)
            let tx = ic.maxX + ch * 0.18
            let tw = card.maxX - ch * 0.16 - tx
            let ts = ch * 0.3
            let minutes = Int(max(0, t - note.time) / 60)
            let am = measure(minutes < 1 ? "ahora" : "\(minutes) min", size: ts * 0.78, bold: false, color: p.dim)
            put(am, x: card.maxX - ch * 0.16 - am.width, baseline: card.minY + ch * 0.13 + ts * 0.95, ctx)
            wrapped(note.title, sizes: [ts], color: p.text, x: tx, top: card.minY + ch * 0.13, width: tw - am.width - 6, maxLines: 1, ctx)
            wrapped(s.privacy ? "Contenido oculto" : note.text, sizes: [ts * 0.85], color: p.dim, x: tx, top: card.minY + ch * 0.53, width: tw, maxLines: 1, ctx)
            y += ch + gap
        }
    }

    func dashNoticeIcon(_ kind: NoticeKind, _ r: CGRect, _ p: HUDPalette, _ ctx: CGContext) {
        let color: CGColor
        switch kind {
        case .nav: color = p.accent
        case .link: color = p.good
        case .battery: color = p.warn
        case .test: color = p.dim
        }
        fillRounded(r, radius: r.width * 0.28, color: color, ctx)
        let w = r.width
        ctx.setFillColor(p.onAccent)
        ctx.setStrokeColor(p.onAccent)
        ctx.setLineWidth(w * 0.09)
        switch kind {
        case .nav:
            HUDIcons.draw(.straight, in: r.insetBy(dx: w * 0.16, dy: w * 0.16), color: p.onAccent, hole: color, ctx: ctx)
        case .link:
            ctx.fillEllipse(in: CGRect(x: r.midX - w * 0.09, y: r.midY - w * 0.09, width: w * 0.18, height: w * 0.18))
            ctx.strokeEllipse(in: r.insetBy(dx: w * 0.24, dy: w * 0.24))
        case .battery:
            let body = CGRect(x: r.minX + w * 0.22, y: r.midY - w * 0.14, width: w * 0.48, height: w * 0.28)
            ctx.stroke(body)
            ctx.fill(CGRect(x: body.maxX + w * 0.03, y: r.midY - w * 0.06, width: w * 0.06, height: w * 0.12))
            ctx.fill(CGRect(x: body.minX + w * 0.05, y: body.minY + w * 0.05, width: w * 0.12, height: w * 0.18))
        case .test:
            ctx.fillEllipse(in: r.insetBy(dx: w * 0.3, dy: w * 0.3))
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
