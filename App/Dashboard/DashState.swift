// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Estado del panel listo para dibujar. La app lo escribe desde el hilo principal y el dibujo
/// para la moto lo lee desde el suyo.
final class DashState {
    static let shared = DashState()

    /// Duración de las transiciones (colores de la música, ruta nueva).
    static let fade = 0.3
    /// 0.6.4: duración del cambio del botón central entre reproducir y pausa.
    static let playFade = 0.25

    private let lock = NSLock()
    private var base = DashSnapshot()
    private var noticeSeconds: Double = 8
    private var animations = true
    /// Colores de la canción anterior y momento del cambio.
    private var paletteFrom: ArtPalette?
    private var paletteChanged: TimeInterval = 0
    /// Fundido entre la canción anterior y la nueva (portada y textos).
    private var track = TrackTransition()
    /// 0.6.4: momento en que la música pasó de sonar a pausa o al revés (misma canción).
    private var playChanged: TimeInterval = -1_000_000
    /// Ruta que se está mostrando y momento en que cambió (para el fundido al recalcular).
    private weak var lastShape: HUDRouteShape?
    private var shapeChanged: TimeInterval = 0
    /// Última posición conocida, para decidir día o noche aunque no haya ruta.
    private var lastPlace: GeoPoint?

    func apply(_ c: DashConfig) {
        lock.lock()
        base.layout = c.layout
        base.theme = c.theme
        base.privacy = c.noticePrivacy
        base.showArtwork = c.showArtwork
        base.showProgress = c.showProgress
        base.mapSettings = c.map
        base.musicStyle = c.musicStyle
        base.musicIntensity = c.musicIntensity
        base.artworkSize = c.artworkSize
        base.showArtist = c.showArtist
        base.showSource = c.showSource
        animations = c.animations
        noticeSeconds = c.noticeSeconds
        lock.unlock()
        TFTMap.shared.configure(c.map)
    }

    func currentLayout() -> DashLayout {
        lock.lock()
        defer { lock.unlock() }
        return base.layout
    }

    var animationsOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return animations
    }

    /// Noche o día: lo decide el tema del panel; en automático, el amanecer y el atardecer
    /// donde estás (sin posición, la hora local).
    func isNight(_ navStyle: HUDStyle, now: Date = Date()) -> Bool {
        lock.lock()
        var place = lastPlace
        lock.unlock()
        // Antes del primer fotograma todavía no hay posición guardada: se usa la del GPS.
        if place == nil { place = HUDState.shared.get().here }
        return night(at: now, place: place)
    }

    /// Tema para un momento y un lugar. Sirve también para preparar el mapa de lo que viene:
    /// un tramo por el que se pasará después del atardecer se guarda ya en oscuro.
    /// 0.6.5: la moto usa el tema del mapa guardado porque no hay imágenes del tema elegido.
    private(set) var themeFollowsMap = false

    private func noteThemeFollowsMap(_ follow: Bool, night: Bool) {
        lock.lock()
        let changed = follow != themeFollowsMap
        themeFollowsMap = follow
        lock.unlock()
        guard changed else { return }
        logLine(follow
            ? "[TEMA] la moto usa el tema del mapa guardado (\(night ? "oscuro" : "claro")) hasta tener imágenes del tema elegido"
            : "[TEMA] la moto vuelve al tema elegido")
    }

    func night(at date: Date, place: GeoPoint?) -> Bool {
        lock.lock()
        let theme = base.theme
        lock.unlock()
        switch theme {
        case .dark: return true
        case .light: return false
        case .auto:
            if let g = place, let n = SunClock.isNight(at: date, lat: g.lat, lon: g.lon) { return n }
            return SunClock.isNightByClock(date)
        }
    }

    func setMusic(_ m: MusicSnapshot) {
        let t = Date().timeIntervalSinceReferenceDate
        lock.lock()
        if m.palette != base.music.palette {
            paletteFrom = base.music.palette
            paletteChanged = t
        }
        if TrackTransition.key(base.music) == TrackTransition.key(m) && base.music.playing != m.playing {
            playChanged = t
        }
        track.update(old: base.music, new: m, at: t)
        base.music = m
        lock.unlock()
    }

    func setExternal(_ e: ExternalGuide?) {
        lock.lock()
        base.external = e
        lock.unlock()
    }

    func post(_ n: NoticeSnapshot) {
        lock.lock()
        base.notices.append(n)
        if base.notices.count > 12 { base.notices.removeFirst(base.notices.count - 12) }
        lock.unlock()
    }

    /// Estado actual con la navegación al día y solo los avisos que aún no caducan.
    func snapshot(now: Date = Date()) -> DashSnapshot {
        let nav = HUDState.shared.get()
        let t = now.timeIntervalSinceReferenceDate
        lock.lock()
        if let here = nav.here { lastPlace = here }
        var s = base
        let keep = noticeSeconds
        base.notices.removeAll { t - $0.time > 600 }
        // Transición de colores al cambiar de canción (al mismo ritmo que la portada y los textos).
        if animations && t - paletteChanged < TrackTransition.duration {
            s.paletteFrom = paletteFrom
            s.paletteFade = max(0, (t - paletteChanged) / TrackTransition.duration)
        }
        if animations, let f = track.fade(at: t) {
            s.musicFrom = track.from
            s.musicFade = f
        }
        if animations, let f = track.artFade(at: t) {
            s.artFrom = track.artFrom
            s.artFade = f
        }
        // 0.6.4: el botón central cambia de ▶ a ❚❚ (o al revés) con un fundido corto.
        if animations && t - playChanged < DashState.playFade {
            s.playFade = max(0, (t - playChanged) / DashState.playFade)
        }
        // Fundido de entrada de una ruta nueva (al recalcular).
        if let shape = nav.shape, shape !== lastShape {
            if lastShape != nil { shapeChanged = t }
            lastShape = shape
        }
        if animations && t - shapeChanged < DashState.fade * 1.5 {
            s.routeFade = max(0.15, (t - shapeChanged) / (DashState.fade * 1.5))
        }
        let anim = animations
        lock.unlock()
        s.nav = nav
        s.notices = s.notices.filter { t - $0.time <= keep }
        s.night = isNight(nav.style, now: now)
        if s.layout.showsMap {
            s.map = TFTMap.shared.base(for: nav, now: now)
            s.mapCoverage = TFTMap.shared.coverageState()
            if anim, let fade = TFTMap.shared.styleFade(now: now), fade.to === s.map {
                s.mapFrom = fade.from
                s.mapFade = fade.t
            }
        }
        // 0.6.5: el tema de la moto sigue al del mapa que se ve. Con el iPhone bloqueado solo hay
        // imágenes guardadas; si la que toca es del otro tema (cambio de tema, o el atardecer o el
        // amanecer llegó antes o después de lo previsto) salía el tema claro con el mapa oscuro.
        let follow = s.map.map { $0.night != s.night } ?? false
        if follow, let m = s.map { s.night = m.night }
        noteThemeFollowsMap(follow, night: s.night)
        return s
    }
}
