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
            // La zona que queda debajo de la hora la deja libre (la brújula baja, el texto empieza
            // más abajo y la cabecera de la música se acorta).
            statusReserve = f.rect.intersects(clock) ? clock : nil
            compassDrop = statusReserve.map { max(0, $0.maxY - f.rect.minY - 4 * k) } ?? 0
            let radius = 14 * k
            ctx.addPath(CGPath(roundedRect: f.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
            ctx.setFillColor(p.panel)
            ctx.fill(f.rect)
            switch f.module {
            case .nav: dashNav(s, p, now, f.rect, ctx)
            case .turn: dashTurn(s.nav, p, belowStatus(f.rect), ctx)
            case .map: dashMap(s, p, now, f.rect, ctx)
            case .trip: dashTrip(s.nav, p, now, belowStatus(f.rect), ctx)
            case .music:
                if MusicStageLayout.fits(f.rect, k: k) {
                    dashMusicStage(s, p, now, f.rect, ctx)
                } else {
                    dashMusic(s, p, now, f.rect, ctx)
                }
            case .notices: dashNotices(s, p, now, belowStatus(f.rect), ctx)
            case .clock: dashClock(p, now, belowStatus(f.rect), ctx)
            }
            ctx.restoreGState()
        }
        compassDrop = 0
        statusReserve = nil
        if strip {
            let r = CGRect(x: area.minX, y: area.maxY + gap, width: area.width, height: 62 * k)
            dashTurnStrip(s.nav, p, r, ctx)
        }

        dashStatusClock(p, now, clock, ctx)
        var right = clock.minX - 8 * k
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
                let compact = o.maneuverSize == .compact
                let radius = (compact ? 16 : 18) * k
                if let ext = s.external, !n.navigating {
                    let small = CGRect(x: r.minX, y: r.minY, width: r.width, height: min(r.height, 112 * k))
                    cardBackground(small, p, ctx, radius: radius)
                    dashExternalCard(ext, s, p, now, small, ctx)
                } else if n.navigating || n.arrived || !n.previewRoutes.isEmpty {
                    cardBackground(r, p, ctx, radius: radius)
                    if compact { dashTurnCompact(n, p, r, ctx) } else { dashTurnContent(n, p, r, ctx) }
                } else {
                    let small = CGRect(x: r.minX, y: r.minY, width: r.width, height: min(r.height, (compact ? 66 : 92) * k))
                    cardBackground(small, p, ctx, radius: radius)
                    if compact { dashTurnCompact(n, p, small, ctx) } else { dashTurnContent(n, p, small, ctx) }
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
            case .time:
                dashStatusClock(p, now, r, ctx)
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
        let t = min(r.height - 2 * pad, 64 * k, r.width * 0.26)
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
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
            wrapped("Guía en \(ext.provider.title)", sizes: [13 * k, 11.5 * k], color: p.accent, x: tx, top: r.minY + pad, width: tw, maxLines: 1, ctx)
            wrapped(ext.name, sizes: [20 * k, 17 * k, 15 * k], color: p.text, x: tx, top: r.minY + pad + 18 * k, width: tw, maxLines: 1, ctx)
            wrapped("A \(HUDFormat.distance(km)) en línea recta", sizes: [14 * k, 12 * k], color: p.dim, x: tx, top: r.minY + pad + 46 * k, width: tw, maxLines: 1, ctx)
        } else {
            let tx = tile.maxX + 12 * k
            wrapped("Guía en \(ext.provider.title)", sizes: [18 * k, 15 * k], color: p.text, x: tx, top: r.minY + pad, width: r.maxX - pad - tx, maxLines: 1, ctx)
            wrapped(ext.name, sizes: [15 * k, 13 * k], color: p.dim, x: tx, top: r.minY + pad + 26 * k, width: r.maxX - pad - tx, maxLines: 1, ctx)
        }
    }

    /// Barra de viaje (0.6.2): "Llegada 7:22 p.m. | 18 min | 7.4 km" y el avance. Sin ruta no
    /// se dibuja: la hora actual está siempre arriba a la derecha y no se confunde con la llegada.
    func dashTripPill(_ n: HUDSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        guard n.navigating && !n.arrived else { return }
        drawTripLine(n, p, r, valueSize: 22 * k, alignRight: false, progress: true, ctx)
    }

    /// Las tres cifras del viaje separadas: la llegada con su etiqueta, el tiempo y la distancia.
    func drawTripLine(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, valueSize: CGFloat, alignRight: Bool,
                      progress: Bool, _ ctx: CGContext) {
        let t = HUDFormat.tripParts(n)
        func parts(_ v: CGFloat) -> [Measured] {
            [measure(t.label, size: v * 0.62, bold: true, color: p.dim),
             measure(t.eta, size: v, bold: true, color: p.text),
             measure(t.suffix, size: v * 0.55, bold: true, color: p.dim),
             measure(t.remaining, size: v, bold: true, color: p.text),
             measure(t.distance, size: v, bold: true, color: p.text)]
        }
        func width(_ m: [Measured], _ v: CGFloat) -> CGFloat {
            m[0].width + v * 0.3 + m[1].width + v * 0.16 + m[2].width + 2 * v * 1.2 + m[3].width + m[4].width
        }
        var v = valueSize
        var m = parts(v)
        let maxW = r.width - 1.6 * v
        if width(m, v) > maxW {
            v *= max(0.6, maxW / width(m, v))
            m = parts(v)
        }
        let content = width(m, v)
        let w = min(r.width, content + 1.6 * v)
        let pill = CGRect(x: alignRight ? r.maxX - w : r.midX - w / 2, y: r.minY, width: w, height: r.height)
        cardBackground(pill, p, ctx, radius: r.height / 2)
        let lift = progress ? 1.5 * k : 0
        let base = pill.midY + (m[1].ascent - m[1].descent) / 2 - lift
        var x = pill.midX - content / 2
        put(m[0], x: x, baseline: base, ctx)
        x += m[0].width + v * 0.3
        put(m[1], x: x, baseline: base, ctx)
        x += m[1].width + v * 0.16
        put(m[2], x: x, baseline: base, ctx)
        x += m[2].width
        for value in [m[3], m[4]] {
            ctx.setFillColor(alpha(p.text, 0.28))
            ctx.fill(CGRect(x: x + v * 0.6 - 0.75 * k, y: pill.midY - lift - v * 0.42, width: 1.5 * k, height: v * 0.84))
            x += v * 1.2
            put(value, x: x, baseline: base, ctx)
            x += value.width
        }
        guard progress else { return }
        let f = CGFloat(max(0, min(1, n.fraction)))
        let track = CGRect(x: pill.minX + r.height * 0.45, y: pill.maxY - 6 * k, width: pill.width - r.height * 0.9, height: 3 * k)
        fillRounded(track, radius: 1.5 * k, color: alpha(p.line, 0.9), ctx)
        if f > 0.01 {
            fillRounded(CGRect(x: track.minX, y: track.minY, width: track.width * f, height: track.height), radius: 1.5 * k, color: p.accent, ctx)
        }
    }

    /// La hora actual (0.6.2): pequeña y siempre en el mismo sitio, arriba a la derecha.
    func dashStatusClock(_ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let c = HUDFormat.clock(now)
        cardBackground(r, p, ctx, radius: r.height / 2)
        let t = measure(c.time, size: 19 * k, bold: true, color: p.text)
        let sfx = measure(c.suffix, size: 11 * k, bold: true, color: p.dim)
        let x = r.midX - (t.width + 4 * k + sfx.width) / 2
        let base = r.midY + (t.ascent - t.descent) / 2
        put(t, x: x, baseline: base, ctx)
        put(sfx, x: x + t.width + 4 * k, baseline: base, ctx)
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

    func dashMap(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext, anchorX: CGFloat = 0.5,
                 compassBottom: Bool = false, compassLift: CGFloat = 0) {
        let size = 40 * k
        let compass = compassBottom
            ? CGRect(x: r.maxX - size - 10 * k, y: r.maxY - size - 10 * k - compassLift, width: size, height: size)
            : CGRect(x: r.maxX - size - 10 * k, y: r.minY + 10 * k + compassDrop, width: size, height: size)
        if drawStreetMap(s, p, now, r, ctx, compass: compass) { return }
        let u = max(0.5, min(r.width, r.height) / 400)
        let anchor = CGPoint(x: r.minX + r.width * anchorX, y: r.maxY - r.height * 0.24)
        drawMiniMap(s.nav, p, now, r, ctx, anchor: anchor, unit: u, divider: false)
    }

    func dashNav(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let n = s.nav
        let wide = r.width > r.height * 1.25
        let pad = (r.height * 0.03).rounded() + 2
        let tripSize = max(11, r.height * 0.062)
        let tripH = tripSize * 1.9
        let showTrip = n.navigating && !n.arrived
        // Con la tarjeta a todo el ancho (zona estrecha, como en Pantalla dividida), la brújula
        // va abajo a la derecha, encima de los datos del viaje, para no quedar tapada.
        dashMap(s, p, now, r, ctx, anchorX: wide ? 0.74 : 0.5, compassBottom: !wide,
                compassLift: !wide && showTrip ? tripH + pad * 0.5 : 0)
        var card: CGRect
        if wide {
            card = CGRect(x: r.minX + pad, y: r.minY + pad, width: min(r.width * 0.5, r.height * 1.25), height: r.height * 0.62)
        } else {
            card = CGRect(x: r.minX + pad, y: r.minY + pad, width: r.width - 2 * pad, height: r.height * 0.4)
        }
        // Si la hora cae encima, la tarjeta se estrecha o baja para no taparla.
        if let c = statusReserve, c.intersects(card) {
            let narrow = c.minX - 8 * k - card.minX
            if narrow >= card.width * 0.6 {
                card.size.width = narrow
            } else {
                card.origin.y = c.maxY + 6 * k
            }
        }
        if let ext = s.external, !n.navigating {
            let small = CGRect(x: card.minX, y: card.minY, width: card.width, height: min(card.height, 112 * k))
            fillRounded(small, radius: small.height * 0.14, color: alpha(p.background, 0.93), ctx)
            dashExternalCard(ext, s, p, now, small, ctx)
            return
        }
        fillRounded(card, radius: card.height * 0.1, color: alpha(p.background, 0.93), ctx)
        dashTurnContent(n, p, card, ctx)

        if showTrip {
            // A la derecha: el logotipo de Mapas de Apple (abajo a la izquierda) queda a la vista.
            let row = CGRect(x: r.minX + pad + 70 * k, y: r.maxY - pad - tripH, width: r.width - 2 * pad - 70 * k, height: tripH)
            drawTripLine(n, p, row, valueSize: tripSize, alignRight: true, progress: false, ctx)
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
        } else if !n.navigating && n.previewRoutes.indices.contains(n.previewSelected) {
            // Antes de empezar: la ruta elegida, su distancia y su tiempo.
            let i = n.previewSelected
            let parts = HUDFormat.distanceParts(n.previewDistances.indices.contains(i) ? n.previewDistances[i] : 0)
            big = parts.value
            unit = parts.unit
            kind = .depart
            var text = n.previewRoutes.count > 1 ? "Ruta \(i + 1) de \(n.previewRoutes.count)" : "Ruta lista"
            if n.previewTimes.indices.contains(i) { text += " · " + HUDFormat.durationCompact(n.previewTimes[i]) }
            line = text + " · Toca Iniciar en el iPhone"
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
            ((clock?.time ?? "--:--") + " " + (clock?.suffix ?? ""), "Llegada"),
            (HUDFormat.durationCompact(n.remainingTime), "Tiempo restante"),
            (HUDFormat.distance(n.remainingDistance), "Distancia"),
        ]
        let barH = max(3, r.height * 0.035)
        let inner = CGRect(x: r.minX + pad, y: r.minY + pad, width: r.width - 2 * pad, height: r.height - 2 * pad - barH - pad * 0.5)
        if inner.width >= 300 {
            let cw = inner.width / 3
            let vs = min(inner.height * 0.42, cw * 0.3)
            for (i, item) in items.enumerated() {
                var v = measure(item.0, size: vs, bold: true, color: p.text)
                if v.width > cw - 8 { v = measure(item.0, size: vs * max(0.6, (cw - 8) / v.width), bold: true, color: p.text) }
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
        // La hora actual puede caer en esta zona (columna de la derecha): el contenido va debajo.
        let r = belowStatus(r)
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

    // MARK: - Maniobra compacta (0.6.2)

    /// Tarjeta compacta de la maniobra: flecha pequeña, distancia y calle, con márgenes justos
    /// para tapar poco mapa. La instrucción completa sigue en la tarjeta grande y en la pantalla
    /// dividida; aquí el giro lo dice la flecha.
    func dashTurnCompact(_ n: HUDSnapshot, _ p: HUDPalette, _ r: CGRect, _ ctx: CGContext) {
        let pad = 9 * k
        let preview = !n.navigating && n.previewRoutes.indices.contains(n.previewSelected)
        if !n.navigating && !n.arrived && !preview {
            // Sin ruta: tarjeta baja.
            let t = min(40 * k, r.height - 2 * pad)
            let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
            fillRounded(tile, radius: t * 0.24, color: p.line, ctx)
            HUDIcons.draw(.depart, in: tile.insetBy(dx: t * 0.16, dy: t * 0.16), color: p.dim, hole: p.line, ctx: ctx)
            let tx = tile.maxX + 9 * k
            let tw = r.maxX - pad - tx
            wrapped("Sin ruta", sizes: [19 * k, 17 * k], color: p.text, x: tx, top: r.minY + pad - 2 * k, width: tw, maxLines: 1, ctx)
            wrapped("Elige un destino en el iPhone", sizes: [12 * k, 11 * k], color: p.dim, x: tx, top: r.minY + pad + 21 * k, width: tw, maxLines: 2, ctx)
            return
        }
        let t = min(50 * k, r.height * 0.54)
        let tile = CGRect(x: r.minX + pad, y: r.minY + pad, width: t, height: t)
        var color = p.accent
        var kind = n.kind
        var big = ""
        var unit = ""
        var line = HUDFormat.street(from: n.instruction) ?? n.instruction
        var lineColor = p.text
        if n.arrived {
            color = p.good
            kind = .arrive
            big = "Llegaste"
            line = n.destinationName
        } else if preview {
            let i = n.previewSelected
            let parts = HUDFormat.distanceParts(n.previewDistances.indices.contains(i) ? n.previewDistances[i] : 0)
            big = parts.value
            unit = parts.unit
            kind = .depart
            line = n.previewRoutes.count > 1 ? "Ruta \(i + 1) de \(n.previewRoutes.count)" : "Ruta lista"
            if n.previewTimes.indices.contains(i) { line += " · " + HUDFormat.durationCompact(n.previewTimes[i]) }
        } else {
            let parts = HUDFormat.distanceParts(n.distanceToManeuver)
            big = parts.value
            unit = parts.unit
            if n.rerouting {
                color = p.warn
                line = "Recalculando…"
                lineColor = p.warn
            }
        }
        fillRounded(tile, radius: t * 0.24, color: color, ctx)
        HUDIcons.draw(kind, in: tile.insetBy(dx: t * 0.13, dy: t * 0.13), color: p.onAccent, hole: color, ctx: ctx)

        let showThen = n.thenKind != nil && n.navigating && !n.rerouting && !n.arrived
        let chip = 22 * k
        let tx = tile.maxX + 9 * k
        let tw = r.maxX - pad - tx - (showThen ? chip + 4 * k : 0)
        var size = unit.isEmpty ? 24 * k : 38 * k
        var m = measure(big, size: size, bold: true, color: p.text)
        var um = measure(unit, size: size * 0.45, bold: true, color: p.dim)
        let need = m.width + (unit.isEmpty ? 0 : size * 0.1 + um.width)
        if need > tw, need > 0 {
            size *= max(0.5, tw / need)
            m = measure(big, size: size, bold: true, color: p.text)
            um = measure(unit, size: size * 0.45, bold: true, color: p.dim)
        }
        let base = tile.midY + (m.ascent - m.descent) / 2
        put(m, x: tx, baseline: base, ctx)
        if !unit.isEmpty { put(um, x: tx + m.width + size * 0.1, baseline: base, ctx) }
        if showThen, let then = n.thenKind {
            // La maniobra siguiente, pequeña y atenuada, arriba a la derecha.
            let c = CGRect(x: r.maxX - pad - chip, y: tile.minY, width: chip, height: chip)
            fillRounded(c, radius: chip * 0.28, color: alpha(p.text, 0.1), ctx)
            HUDIcons.draw(then, in: c.insetBy(dx: chip * 0.15, dy: chip * 0.15), color: p.dim, hole: p.background, ctx: ctx)
        }
        let top = tile.maxY + 5 * k
        if r.maxY - top > 12 * k {
            wrapped(line, sizes: [19 * k, 17 * k, 15 * k], color: lineColor, x: r.minX + pad, top: top, width: r.width - 2 * pad, maxLines: 1, ctx)
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
            while start < total && lines.count < maxLines {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                if count <= 0 { break }
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
                lastStart = start
                start += count
            }
            if start < total && size != smallest { continue }
            let fits = start >= total
            if !fits, !lines.isEmpty {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: lastStart, length: total - lastStart))
                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
                if let cut = CTLineCreateTruncatedLine(rest, Double(width), .end, ellipsis) { lines[lines.count - 1] = cut }
            }
            return (lines.map { measured($0) }, size, fits)
        }
        return ([], smallest, false)
    }

    /// Pantalla de música completa, al estilo de CarPlay: fondo con los colores de la portada,
    /// portada grande a la derecha, título y artista centrados, el estado y la barra de progreso
    /// con el tiempo transcurrido y la duración. No dibuja botones: la pantalla de la moto no es
    /// táctil para la app y el protocolo no envía teclas, así que la música se controla desde
    /// el iPhone (o el intercomunicador).
    func dashMusicStage(_ s: DashSnapshot, _ p: HUDPalette, _ now: Date, _ r: CGRect, _ ctx: CGContext) {
        let m = s.music
        let c = musicColors(s)
        let L = MusicStageLayout.make(r, k: k, artwork: s.showArtwork, size: s.artworkSize, reserve: statusReserve)
        drawStageBackground(s, c, L, r, ctx)
        let has = m.available && !m.title.isEmpty
        if s.showSource && has && L.header.width > 40 * k {
            let src = textLines(m.source.uppercased(), sizes: [15 * k], bold: true, color: sourceColor(m, c), width: L.header.width, maxLines: 1)
            if let line = src.lines.first { put(line, x: L.header.minX, baseline: L.header.midY + (line.ascent - line.descent) / 2, ctx) }
        }
        // Al cambiar de canción la portada se funde de una a otra; los textos, uno después del
        // otro (la anterior sale hacia arriba y la nueva entra desde abajo), sin mezclarse.
        let f = CGFloat(max(0, min(1, s.musicFade)))
        if let old = s.musicFrom, s.musicFade < 1 {
            let out = min(1, 2 * f)
            let into = max(0, 2 * f - 1)
            stageTrack(old, s, c, L, p, artAlpha: 1 - f, textAlpha: 1 - out, dy: -10 * k * out, art: old.artwork, artFrom: nil, artFade: 1, ctx)
            stageTrack(m, s, c, L, p, artAlpha: f, textAlpha: into, dy: 10 * k * (1 - into), art: m.artwork, artFrom: nil, artFade: 1, ctx)
        } else {
            stageTrack(m, s, c, L, p, artAlpha: 1, textAlpha: 1, dy: 0, art: m.artwork, artFrom: s.artFrom, artFade: CGFloat(s.artFade), ctx)
        }
        guard has, s.showProgress, m.duration > 1 else { return }
        let elapsed = m.playing ? max(0, now.timeIntervalSinceReferenceDate - m.positionTime) : 0
        let pos = max(0, min(m.duration, m.position + elapsed))
        let ts = 18 * k
        let a = measure(dashTime(pos), size: ts, bold: true, color: c.secondary.cg)
        let b = measure(dashTime(m.duration), size: ts, bold: true, color: c.secondary.cg)
        // Ancho fijo para los tiempos: la barra no se mueve al cambiar los segundos.
        let label = max(measure(m.duration >= 600 ? "88:88" : "8:88", size: ts, bold: true, color: c.secondary.cg).width, a.width, b.width)
        let barH = 6 * k
        let bar = CGRect(x: L.progress.minX + label + 14 * k, y: L.progress.midY - barH / 2,
                         width: max(0, L.progress.width - 2 * (label + 14 * k)), height: barH)
        fillRounded(bar, radius: barH / 2, color: c.track.cg, ctx)
        let done = bar.width * CGFloat(pos / m.duration)
        if done > 1 {
            fillRounded(CGRect(x: bar.minX, y: bar.minY, width: done, height: barH), radius: barH / 2, color: c.accent.cg, ctx)
        }
        let baseline = L.progress.midY + (a.ascent - a.descent) / 2
        put(a, x: bar.minX - 14 * k - a.width, baseline: baseline, ctx)
        put(b, x: bar.maxX + 14 * k, baseline: baseline, ctx)
    }

    /// Fondo: degradado con los colores de la portada y un resplandor suave detrás de ella. Solo
    /// cambia con la canción, así que se dibuja una vez y se reutiliza (salvo durante el fundido).
    func drawStageBackground(_ s: DashSnapshot, _ c: MusicCardColors, _ L: MusicStageLayout, _ r: CGRect, _ ctx: CGContext) {
        var glow = c.accent
        if let base = s.music.palette?.base {
            let h = base.hsl
            glow = s.night ? RGB(h: h.h, s: min(h.s, 0.6), l: 0.42) : RGB(h: h.h, s: min(h.s, 0.6) * 0.8, l: 0.8)
        }
        let center = L.artwork.width > 0 ? CGPoint(x: L.artwork.midX, y: L.artwork.midY) : CGPoint(x: r.maxX - r.width * 0.25, y: r.midY)
        func paint(_ g: CGContext) {
            drawMusicBackground(r, c, radius: 0, alpha: 1, g)
            let colors = [glow.cg.copy(alpha: s.night ? 0.5 : 0.4) ?? glow.cg, glow.cg.copy(alpha: 0) ?? glow.cg] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return }
            g.saveGState()
            g.clip(to: r)
            g.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                 endRadius: max(r.width, r.height) * 0.55, options: [])
            g.restoreGState()
        }
        let w = Int(r.width.rounded())
        let h = Int(r.height.rounded())
        guard HUDRenderer.cacheStageBackground, s.paletteFade >= 1, w > 0, h > 0 else {
            paint(ctx)
            return
        }
        func rgb(_ x: RGB) -> String { String(format: "%.3f,%.3f,%.3f", x.r, x.g, x.b) }
        let key = [String(format: "%.0f,%.0f,%d,%d,%.0f,%.0f", r.minX, r.minY, w, h, center.x, center.y),
                   rgb(c.top), rgb(c.bottom), rgb(glow), s.night ? "n" : "d"].joined(separator: "|")
        if stageBackground?.key != key {
            let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            guard let off = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else {
                paint(ctx)
                return
            }
            // Misma orientación que la imagen de la moto (origen arriba a la izquierda).
            off.translateBy(x: 0, y: CGFloat(h))
            off.scaleBy(x: 1, y: -1)
            off.translateBy(x: -r.minX, y: -r.minY)
            paint(off)
            guard let image = off.makeImage() else {
                paint(ctx)
                return
            }
            stageBackground = (key, image)
        }
        guard let image = stageBackground?.image else { return }
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY + CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    /// Portada, título, artista, álbum y estado de una canción (con transparencia y desplazamiento
    /// para la transición).
    func stageTrack(_ m: MusicSnapshot, _ s: DashSnapshot, _ c: MusicCardColors, _ L: MusicStageLayout, _ p: HUDPalette,
                    artAlpha: CGFloat, textAlpha: CGFloat, dy: CGFloat, art: CGImage?, artFrom: CGImage?, artFade: CGFloat,
                    _ ctx: CGContext) {
        let has = m.available && !m.title.isEmpty
        if L.artwork.width > 4 && artAlpha > 0.01 {
            ctx.saveGState()
            ctx.setAlpha(artAlpha)
            // Sombra suave sin desenfoque (tres capas), para dar relieve sin gastar CPU.
            for i in 1...3 {
                let d = CGFloat(i)
                fillRounded(L.artwork.offsetBy(dx: 0, dy: (2 + d * 2) * k).insetBy(dx: -d * 1.5 * k, dy: -d * 1.5 * k),
                            radius: (8 + d * 2) * k, color: CGColor(gray: 0, alpha: s.night ? 0.12 : 0.06), ctx)
            }
            if artFade < 1 {
                dashArtwork(has ? artFrom : nil, L.artwork, p, ctx)
                ctx.setAlpha(artAlpha * max(0, artFade))
            }
            dashArtwork(has ? art : nil, L.artwork, p, ctx)
            ctx.restoreGState()
        }
        guard textAlpha > 0.01 else { return }
        ctx.saveGState()
        ctx.setAlpha(textAlpha)
        let w = L.text.width
        var blocks: [(lines: [Measured], gap: CGFloat)] = []
        if has {
            // El título en una línea si cabe con letra grande; si no, en dos.
            var title = textLines(m.title, sizes: [40 * k, 36 * k, 33 * k], bold: true, color: c.text.cg, width: w, maxLines: 1)
            if !title.fits {
                title = textLines(m.title, sizes: [36 * k, 32 * k, 28 * k], bold: true, color: c.text.cg, width: w, maxLines: 2)
            }
            blocks.append((title.lines, 0))
            if s.showArtist && !m.artist.isEmpty {
                blocks.append((textLines(m.artist, sizes: [25 * k, 22 * k, 20 * k], bold: false, color: c.text.cg, width: w, maxLines: 1).lines, 8 * k))
            }
            if s.showArtist && !m.album.isEmpty {
                blocks.append((textLines(m.album, sizes: [19 * k, 17 * k], bold: false, color: c.secondary.cg, width: w, maxLines: 1).lines, 4 * k))
            }
        } else {
            blocks.append((textLines("Sin música", sizes: [36 * k, 30 * k], bold: true, color: c.secondary.cg, width: w, maxLines: 1).lines, 0))
            blocks.append((textLines("Reproduce algo en el iPhone", sizes: [22 * k, 19 * k], bold: false, color: c.secondary.cg, width: w, maxLines: 2).lines, 10 * k))
        }
        let pillH = 36 * k
        var height: CGFloat = 0
        for b in blocks {
            height += b.gap
            for line in b.lines { height += line.ascent + line.descent + 2 * k }
        }
        if has { height += 22 * k + pillH }
        var y = L.text.midY - height / 2 + dy
        for b in blocks {
            y += b.gap
            for line in b.lines {
                put(line, x: L.text.midX - line.width / 2, baseline: y + line.ascent, ctx)
                y += line.ascent + line.descent + 2 * k
            }
        }
        if has {
            // Estado de la reproducción (no es un botón).
            y += 22 * k
            let label = measure(m.playing ? "Reproduciendo" : "En pausa", size: 16 * k, bold: true, color: c.text.cg)
            let g = 13 * k
            let pw = 16 * k + g + 9 * k + label.width + 18 * k
            let pill = CGRect(x: L.text.midX - pw / 2, y: y, width: pw, height: pillH)
            fillRounded(pill, radius: pillH / 2, color: c.text.cg.copy(alpha: 0.13) ?? c.text.cg, ctx)
            let gx = pill.minX + 16 * k
            let gy = pill.midY - g / 2
            ctx.setFillColor(c.text.cg)
            if m.playing {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: gx, y: gy))
                ctx.addLine(to: CGPoint(x: gx + g * 0.9, y: gy + g / 2))
                ctx.addLine(to: CGPoint(x: gx, y: gy + g))
                ctx.closePath()
                ctx.fillPath()
            } else {
                ctx.fill(CGRect(x: gx, y: gy, width: g * 0.3, height: g))
                ctx.fill(CGRect(x: gx + g * 0.55, y: gy, width: g * 0.3, height: g))
            }
            put(label, x: gx + g + 9 * k, baseline: pill.midY + (label.ascent - label.descent) / 2, ctx)
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
