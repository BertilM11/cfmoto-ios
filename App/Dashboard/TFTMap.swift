// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mapa de calles para la moto con instantáneas de Apple Maps (MKMapSnapshotter).
//
// Apple solo entrega instantáneas con la app en primer plano: si se piden en segundo plano,
// llegan cuando la app vuelve a abrirse (documentación de MKMapSnapshotter.start). Por eso:
//  - con la app abierta se piden sin parar, siguiendo la posición (mapa en vivo);
//  - a la vez, y en paralelo, se guarda la ruta por delante: toda la que quepa en la memoria
//    permitida, con una imagen más después de cada giro y con el tema (día/noche) que tocará
//    al pasar por cada tramo;
//  - con el iPhone bloqueado se usan esas imágenes; si no hay ninguna que sirva, el panel vuelve
//    al dibujo simple de la ruta (MAPA SIMPLE).
// Qué falta, cuánto cubre lo guardado y qué imagen usar se decide en MapCorridor.swift.
import Foundation
import MapKit
import UIKit
import os

final class TFTMap {
    static let shared = TFTMap()

    /// Dónde debe quedar la posición dentro de la imagen (fracción del alto, desde arriba).
    static let puckY = MapCorridor.puckY
    /// Imágenes de la ruta que se piden a la vez, además de la de en vivo (0.6.3: 3; eran 2).
    static let parallelPrefetch = MapCorridor.parallelPrefetch
    /// Tope de imágenes guardadas (0.6.3: 800, unos 70 MB con ~90 KB por imagen; eran 400).
    static let maxImages = MapCorridor.maxImages

    /// Estado para la pantalla de diagnóstico.
    struct Stats {
        var foreground = true
        var source = MapSource.none.rawValue
        var sourceAge: Double?
        var liveAge: Double?
        var requests = 0
        var successes = 0
        var failures = 0
        var late = 0
        var discardedLate = 0
        var watchdog = 0
        var inFlight = 0
        var lastError = ""
        var lastSuccess: Date?
        var cached = 0
        var cachedOtherStyle = 0
        var cachedBytes = 0
        var capacity = 0
        var budgetBytes = 0
        var routeActive = false
        var routeRemaining: Double = 0
        var target: Double = 0
        /// Metros entre imágenes guardadas.
        var step: Double = 0
        var coverage = CorridorCoverage.Result(continuous: 0, covered: 0, checked: 0, gaps: 0)
        var wantedStyle = ""
        /// 0.6.3: estado de la cobertura (completa, guardando o parcial) y avisos de memoria.
        var state = MapCoverageState.none
        var memoryWarnings = 0
        /// 0.6.5: imágenes extra pedidas para huecos que la rejilla no veía.
        var gapFills = 0
        /// 0.6.5: fallos seguidos al guardar y segundos que faltan para reintentar.
        var failStreak = 0
        var retryIn: Double = 0
    }

    private let queue = DispatchQueue(label: "cfmoto.tftmap", qos: .userInitiated)
    private let lock = NSLock()

    // Lo que lee el hilo de dibujo (protegido por `lock`).
    private var live: MapBase?
    private var entries: [CorridorEntry] = []
    private var inUse: MapBase?
    private var settings = MapSettings()
    /// Estilo que se quiere ahora (día/noche, tipo de mapa), para preferir esas imágenes.
    private var wantedStyle = ""
    /// Fundido al cambiar de estilo: imagen anterior, nueva y momento del cambio.
    private var fadeFrom: MapBase?
    private weak var fadeTo: MapBase?
    private var fadeStart: TimeInterval = 0
    /// Qué imagen usó el último fotograma (para el diagnóstico).
    private var lastSource = MapSource.none
    private var lastSourceCreated: TimeInterval = 0
    /// Cobertura para el dibujo de la moto (0.6.3).
    private var coverageSummary = MapCoverageState.none

    // Lo demás solo se toca desde el hilo principal.
    private var timer: Timer?
    private var liveSnapshotter: MKMapSnapshotter?
    private var liveToken: UUID?
    private var liveStarted: TimeInterval = 0
    private var prefetchers: [Double: (snapshotter: MKMapSnapshotter, started: TimeInterval, token: UUID)] = [:]
    private var lastLive: Request?
    private weak var routeShape: HUDRouteShape?
    private var previewKey = ""
    private var routeGeneration = 0
    private var route: RoutePath?
    private var turns: [Double] = []
    private var routeProgress = 0.0
    private var routeTarget = 0.0
    /// Separación entre imágenes guardadas: estable mientras la calibración no cambie mucho.
    private var routeStep = 0.0
    private var routeMissingSince: TimeInterval?
    private var capacity = TFTMap.maxImages
    private var budget = 48 << 20
    private var averageBytes = 90_000
    private var coverage = CorridorCoverage.Result(continuous: 0, covered: 0, checked: 0, gaps: 0)
    private var coverageTime: TimeInterval = 0
    private var wasActive = true
    private var backgroundLogTime: TimeInterval = 0
    private var requests = 0
    private var successes = 0
    private var failureCount = 0
    private var late = 0
    private var discardedLate = 0
    private var watchdogCancels = 0
    private var lastSuccess: Date?
    /// Metros de terreno a lo alto de la imagen por cada metro de distancia de la cámara
    /// (se ajusta con cada instantánea: no depende de suponer el campo de visión de Apple).
    private var heightPerDistance: [Bool: Double] = [false: 0.62, true: 0.5]
    /// Adelanto del centro respecto a la moto, en fracción de la altura visible.
    private var lookAhead: [Bool: Double] = [false: 0.2, true: 0.12]
    private var failures = 0
    private(set) var lastError = ""
    /// Lo que tarda Apple en entregar una imagen (media), para pedirla ya adelantada.
    private var latency = 0.8
    private var told3D = false
    private var announced = false
    /// 0.6.3: tras un aviso de memoria de iOS se guarda la mitad durante un rato.
    private var pressureUntil: TimeInterval = 0
    private var memoryWarnings = 0
    private var memoryObserver: NSObjectProtocol?
    /// 0.6.5: imágenes pedidas para huecos que la rejilla no vuelve a pedir, y cuántas veces por
    /// sitio (cada 25 m).
    private var gapAttempts: [Int: Int] = [:]
    private var gapFills = 0
    /// 0.6.5: tras un fallo de Apple al guardar se espera antes de volver a pedir (2, 4, 8… hasta
    /// 60 s). Antes se volvía a pedir enseguida, y si Apple estaba limitando las peticiones el
    /// guardado podía quedarse parado.
    private var failStreak = 0
    private var pauseUntil: TimeInterval = 0

    private struct Request {
        let here: GeoPoint
        let center: GeoPoint
        let heading: Double
        let pitch: Double
        let distance: Double
        let night: Bool
        let pixels: CGSize
        let styleKey: String
        let time: TimeInterval
        let anchor: Double
        let visibleHeight: Double
    }

    // MARK: - Arranque y ajustes

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Si iOS avisa de poca memoria, se sueltan las imágenes más lejanas (se vuelven a pedir
        // al acercarse) para que no cierre la app en pleno viaje.
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.memoryWarning() }
    }

    private func memoryWarning() {
        let t = Date().timeIntervalSinceReferenceDate
        memoryWarnings += 1
        pressureUntil = t + 120
        let keep = max(20, capacity / 2)
        lock.lock()
        let before = entries.count
        entries = CorridorPlanner.trim(entries, progress: routeProgress, capacity: keep)
        let after = entries.count
        lock.unlock()
        logLine("[MAPA] aviso de memoria de iOS: se conservan las \(after) imágenes más cercanas de \(before) durante 2 min")
    }

    /// Lo que se dibuja en la moto: cuánta ruta tiene mapa guardado (cualquier hilo).
    func coverageState() -> MapCoverageState {
        lock.lock()
        defer { lock.unlock() }
        return coverageSummary
    }

    func configure(_ s: MapSettings) {
        lock.lock()
        let changed = s != settings
        settings = s
        if changed {
            live = nil
            entries.removeAll()
            inUse = nil
        }
        lock.unlock()
        guard changed else { return }
        let reset = { [weak self] in
            guard let self = self else { return }
            self.lastLive = nil
            self.liveSnapshotter?.cancel()
            self.liveSnapshotter = nil
            self.liveToken = nil
            self.cancelPrefetch()
            self.routeShape = nil
            self.previewKey = ""
            self.route = nil
        }
        if Thread.isMainThread { reset() } else { DispatchQueue.main.async(execute: reset) }
    }

    // MARK: - Lo que usa el dibujo (cualquier hilo)

    /// La imagen de calles que mejor encaja con la posición actual, o nil.
    func base(for n: HUDSnapshot, now: Date) -> MapBase? {
        guard let pose = MapPose.of(n, now: now) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard settings.streets else { return nil }
        let preview = !n.navigating && !n.previewRoutes.isEmpty
        let choice = MapChooser.choose(
            live: live, entries: entries, pose: pose, wantedStyle: wantedStyle,
            now: now.timeIntervalSinceReferenceDate, preview: preview, northUp: settings.northUp
        )
        lastSource = choice.source
        lastSourceCreated = choice.base?.created ?? 0
        guard let b = choice.base else { return nil }
        return use(b)
    }

    /// Fundido en curso al cambiar de estilo (día/noche): imagen anterior, nueva y avance 0…1.
    func styleFade(now: Date) -> (from: MapBase, to: MapBase, t: Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard let from = fadeFrom, let to = fadeTo else { return nil }
        let t = (now.timeIntervalSinceReferenceDate - fadeStart) / 0.3
        guard t < 1 else {
            fadeFrom = nil
            return nil
        }
        return (from, to, max(0, t))
    }

    /// Solo una imagen guardada queda descomprimida a la vez (memoria en segundo plano).
    private func use(_ b: MapBase) -> MapBase {
        if inUse !== b {
            if let old = inUse, !old.live { old.releaseDecoded() }
            inUse = b
        }
        return b
    }

    // MARK: - Diagnóstico (hilo principal)

    func stats() -> Stats {
        let t = Date().timeIntervalSinceReferenceDate
        var s = Stats()
        lock.lock()
        s.source = lastSource.rawValue
        s.sourceAge = lastSourceCreated > 0 ? t - lastSourceCreated : nil
        s.liveAge = live.map { t - $0.created }
        s.cached = entries.count
        s.cachedOtherStyle = entries.filter { $0.base.styleKey != wantedStyle }.count
        s.cachedBytes = entries.reduce(0) { $0 + $1.bytes }
        s.wantedStyle = wantedStyle
        lock.unlock()
        s.foreground = wasActive
        s.requests = requests
        s.successes = successes
        s.failures = failureCount
        s.late = late
        s.discardedLate = discardedLate
        s.watchdog = watchdogCancels
        s.inFlight = prefetchers.count + (liveSnapshotter == nil ? 0 : 1)
        s.lastError = lastError
        s.lastSuccess = lastSuccess
        s.capacity = capacity
        s.budgetBytes = budget
        s.routeActive = route != nil
        s.routeRemaining = route.map { max(0, $0.length - routeProgress) } ?? 0
        s.target = routeTarget
        s.step = routeStep
        s.coverage = coverage
        s.state = coverageState()
        s.memoryWarnings = memoryWarnings
        s.gapFills = gapFills
        s.failStreak = failStreak
        s.retryIn = max(0, pauseUntil - t)
        return s
    }

    /// Resumen de una línea para el registro.
    private func logState(_ prefix: String) {
        let s = stats()
        let mb = Double(s.cachedBytes) / 1_048_576
        var text = String(format: "%@: %d imágenes guardadas (%.1f MB)", prefix, s.cached, mb)
        if s.routeActive {
            text += String(format: ", mapa seguido para %.1f km de los %.1f km que quedan", s.coverage.continuous / 1000, s.routeRemaining / 1000)
        }
        text += ", imagen actual: \(s.source)"
        if s.inFlight > 0 { text += ", pendientes \(s.inFlight)" }
        logLine(text)
    }

    // MARK: - Peticiones (hilo principal)

    private func tick() {
        let t = Date().timeIntervalSinceReferenceDate
        let active = UIApplication.shared.applicationState == .active
        if active != wasActive {
            wasActive = active
            logState(active ? "[MAPA] la app vuelve al frente" : "[MAPA] la app deja el primer plano (Apple no entrega imágenes nuevas hasta que vuelva)")
        }
        if !active && t - backgroundLogTime > 30 {
            backgroundLogTime = t
            logState("[MAPA] en segundo plano")
        }
        if active { watchdog(t) }
        lock.lock()
        let s = settings
        lock.unlock()
        guard s.streets else { return }
        // 0.7: con el mapa propio de OpenStreetMap no se piden imágenes a Apple.
        guard s.provider == .apple else {
            if route != nil { clearRoute() }
            return
        }
        let layout = DashState.shared.currentLayout()
        guard layout.showsMap else { return }
        let n = HUDState.shared.get()
        let now = Date()
        guard let pose = MapPose.of(n, now: now) else { return }
        // El tema, el avance por la ruta y la cobertura se mantienen al día también en segundo
        // plano (solo cálculo, sin MapKit): si anochece con el iPhone bloqueado, el dibujo elige
        // las imágenes oscuras guardadas para ese tramo. Antes se quedaba el tema de cuando la
        // app estaba al frente.
        let night = DashState.shared.isNight(n.style)
        lock.lock()
        wantedStyle = s.styleKey(night: night)
        lock.unlock()
        updateRoute(n, pose, s, now: t)
        guard active else {
            // Sin peticiones: Apple no entrega imágenes hasta que la app vuelve al frente.
            if t - coverageTime > 2 {
                coverageTime = t
                updateCoverage(s)
            }
            return
        }
        let rect = DashLayoutEngine.mapRect(layout, width: 800, height: 400, reservedBottom: HUDRenderer.reservedBottom)
            ?? CGRect(x: 0, y: 0, width: 800, height: 400)
        let pixels = CGSize(width: max(200, (rect.width / 2).rounded() * 2), height: max(120, (rect.height / 2).rounded() * 2))

        let preview = !n.navigating && !n.previewRoutes.isEmpty
        if liveSnapshotter == nil {
            if preview {
                // Antes de empezar: vista general con todas las rutas propuestas.
                requestOverview(n, pose, s, night: night, pixels: pixels, now: now)
            } else {
                // Con ruta, la imagen se pide para el punto de la ruta donde estará la moto
                // cuando llegue (posición y rumbo de ese punto): así el mapa no gira tarde.
                var target = pose
                if let shape = n.shape, let geo = n.geo, let progress = pose.progress, pose.speed > 1 {
                    let ahead = min(shape.length, progress + min(80, pose.speed * latency))
                    target.here = geo.geo(shape.point(at: ahead))
                    var h = shape.bearing(at: ahead, span: 25) * 180 / .pi
                    if h < 0 { h += 360 }
                    target.heading = h
                    target.progress = ahead
                }
                requestLive(target, s, night: night, pixels: pixels, now: now)
            }
        }
        // La ruta por delante se guarda a la vez que el mapa en vivo (antes solo cuando el
        // mapa en vivo no tenía nada que pedir, y en marcha casi nunca se guardaba nada).
        prefetch(n, s, pixels: pixels, now: now)
        if t - coverageTime > 2 {
            coverageTime = t
            updateCoverage(s)
        }
    }

    /// Una instantánea que no llega nunca dejaría el mapa congelado: se cancela y se pide otra.
    private func watchdog(_ t: TimeInterval) {
        if let l = liveSnapshotter, t - liveStarted > 12 {
            l.cancel()
            liveSnapshotter = nil
            liveToken = nil
            lastLive = nil
            watchdogCancels += 1
            logLine("[MAPA] la imagen en vivo no llegó en 12 s: se pide otra")
        }
        let stuck = prefetchers.filter { t - $0.value.started > 25 }.map { $0.key }
        for anchor in stuck {
            prefetchers[anchor]?.snapshotter.cancel()
            prefetchers[anchor] = nil
            watchdogCancels += 1
        }
    }

    /// Distancia de la cámara: más lejos cuanto más rápido, más cerca antes de un giro.
    private func cameraDistance(_ pose: MapPose, _ s: MapSettings) -> Double {
        guard s.autoZoom else { return 700 * s.zoom }
        let kmh = pose.speed * 3.6
        let table: [(Double, Double)] = [(0, 520), (25, 600), (50, 800), (80, 1100), (110, 1450)]
        var d = table.last!.1
        for i in 1..<table.count where kmh <= table[i].0 {
            let (a, da) = table[i - 1]
            let (b, db) = table[i]
            let t = max(0, min(1, (kmh - a) / (b - a)))
            d = da + (db - da) * t
            break
        }
        if let toTurn = pose.toTurn, toTurn < 300 {
            d = min(d, 430 + toTurn * 0.5)
        }
        return d * s.zoom
    }

    private func makeRequest(here: GeoPoint, heading: Double, distance: Double, pitch: Double, night: Bool,
                             pixels: CGSize, s: MapSettings, now: Date, anchor: Double) -> Request {
        let threeD = pitch > 0
        let visible = (heightPerDistance[threeD] ?? 0.6) * distance
        let ahead = (lookAhead[threeD] ?? 0.2) * visible
        let center = heading >= 0 ? here.moved(ahead, bearing: heading) : here
        return Request(
            here: here, center: center, heading: max(0, heading), pitch: pitch, distance: distance, night: night,
            pixels: pixels, styleKey: s.styleKey(night: night), time: now.timeIntervalSinceReferenceDate,
            anchor: anchor, visibleHeight: visible
        )
    }

    private func requestLive(_ pose: MapPose, _ s: MapSettings, night: Bool, pixels: CGSize, now: Date) {
        var heading = s.northUp ? 0 : pose.heading
        if heading < 0 { heading = lastLive?.heading ?? 0 }
        let pitch = s.threeD ? 50.0 : 0
        // La imagen llega con retraso: se pide para donde estará la moto cuando llegue.
        var here = pose.here
        if pose.progress == nil && pose.heading >= 0 && pose.speed > 1 {
            here = here.moved(min(60, pose.speed * latency), bearing: pose.heading)
        }
        let req = makeRequest(here: here, heading: heading, distance: cameraDistance(pose, s), pitch: pitch,
                              night: night, pixels: pixels, s: s, now: now, anchor: -1)
        if let last = lastLive {
            let age = req.time - last.time
            let moved = last.here.distance(to: req.here)
            let turn = headingGap(last.heading, req.heading)
            let zoom = abs(last.distance - req.distance) / max(1, last.distance)
            let stale = last.styleKey != req.styleKey || last.pixels != req.pixels || last.pitch != req.pitch
            let needed = stale || age > 6 || moved > max(6, last.visibleHeight * 0.04) || turn > 5 || zoom > 0.1
            guard needed, age > 0.35 || stale else { return }
        }
        lastLive = req
        startLive(req) { [weak self] base in
            guard let self = self else { return }
            if req.pitch > 0 && !self.told3D {
                self.told3D = true
                logLine(base.perspective > 0.02
                        ? "[MAPA] vista inclinada (3D) aplicada"
                        : "[MAPA] Apple entregó el mapa plano aunque se pidió inclinado")
            }
            self.calibrate(base, req)
            self.setLive(base)
        }
    }

    /// Pide la imagen en vivo. Si llega más de 5 s después (por ejemplo, pedida justo antes de
    /// bloquear el iPhone), ya no corresponde a la posición y se descarta.
    private func startLive(_ req: Request, use: @escaping (MapBase) -> Void) {
        let token = UUID()
        liveToken = token
        liveStarted = req.time
        requests += 1
        liveSnapshotter = snap(req) { [weak self] base, error in
            guard let self = self, self.liveToken == token else { return }
            self.liveSnapshotter = nil
            self.liveToken = nil
            self.finished(base, error: error, req: req)
            guard let base = base else { return }
            let took = Date().timeIntervalSinceReferenceDate - req.time
            if took > 5 {
                self.discardedLate += 1
                self.lastLive = nil
                return
            }
            if took > 0 { self.latency = self.latency * 0.7 + took * 0.3 }
            use(base)
        }
    }

    /// Nueva imagen en vivo; si cambió el estilo, se prepara el fundido desde la anterior.
    private func setLive(_ base: MapBase) {
        lock.lock()
        if let old = live, old.styleKey != base.styleKey {
            fadeFrom = old
            fadeTo = base
            fadeStart = Date().timeIntervalSinceReferenceDate
        }
        live = base
        lock.unlock()
    }

    /// Vista general (norte arriba) que abarca la posición y todas las rutas propuestas.
    private func requestOverview(_ n: HUDSnapshot, _ pose: MapPose, _ s: MapSettings, night: Bool, pixels: CGSize, now: Date) {
        var minLat = pose.here.lat, maxLat = pose.here.lat, minLon = pose.here.lon, maxLon = pose.here.lon
        for route in n.previewRoutes {
            for g in route {
                minLat = min(minLat, g.lat); maxLat = max(maxLat, g.lat)
                minLon = min(minLon, g.lon); maxLon = max(maxLon, g.lon)
            }
        }
        let center = GeoPoint(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2)
        let tall = (maxLat - minLat) * 110_574.0
        let wide = (maxLon - minLon) * 111_320.0 * cos(center.lat * .pi / 180)
        let aspect = Double(pixels.width / max(1, pixels.height))
        let needed = max(tall, wide / aspect, 300) * 1.3
        let distance = needed / (heightPerDistance[false] ?? 0.62)
        let key = s.styleKey(night: night)
        if let last = lastLive, last.pitch == 0, last.heading == 0, last.styleKey == key, last.pixels == pixels,
           last.center.distance(to: center) < needed * 0.05, abs(last.distance - distance) / distance < 0.05 {
            return
        }
        let req = Request(
            here: pose.here, center: center, heading: 0, pitch: 0, distance: distance, night: night, pixels: pixels,
            styleKey: key, time: now.timeIntervalSinceReferenceDate, anchor: -1, visibleHeight: needed
        )
        lastLive = req
        startLive(req) { [weak self] base in self?.setLive(base) }
    }

    /// Ajusta la escala y el adelanto con lo que de verdad devolvió Apple.
    private func calibrate(_ base: MapBase, _ req: Request) {
        let threeD = req.pitch > 0
        // Altura visible: dos puntos separados 50 m en la dirección de la cámara.
        if !threeD, let a = base.project(req.center), let b = base.project(req.center.moved(50, bearing: req.heading)) {
            let fraction = Double(hypot(a.x - b.x, a.y - b.y))
            if fraction > 0.005 {
                let visible = 50 / fraction
                let ratio = visible / req.distance
                if ratio > 0.1 && ratio < 5 {
                    heightPerDistance[false] = (heightPerDistance[false] ?? ratio) * 0.5 + ratio * 0.5
                }
            }
        }
        // Adelanto: que la moto quede a la altura deseada.
        if let q = base.project(req.here), req.heading >= 0 {
            let y = Double(q.y)
            let want = TFTMap.puckY
            var factor = lookAhead[threeD] ?? 0.2
            if y > 0.5 + 0.01 {
                factor *= max(0.6, min(1.6, (want - 0.5) / (y - 0.5)))
            } else {
                factor *= 1.5
            }
            lookAhead[threeD] = max(0.03, min(0.45, factor))
        }
    }

    // MARK: - Ruta guardada

    /// Ruta que se va a recorrer (en curso o propuesta antes de empezar) y avance sobre ella.
    /// Al recalcular, se conservan las imágenes que siguen sirviendo (antes se borraban todas).
    private func updateRoute(_ n: HUDSnapshot, _ pose: MapPose, _ s: MapSettings, now t: TimeInterval) {
        var points: [GeoPoint]?
        var present = false
        if n.navigating, let shape = n.shape, let geo = n.geo {
            present = true
            if shape !== routeShape {
                routeShape = shape
                previewKey = ""
                points = shape.points.map { geo.geo($0) }
            }
        } else if !n.navigating, n.previewRoutes.indices.contains(n.previewSelected) {
            let r = n.previewRoutes[n.previewSelected]
            if let a = r.first, let b = r.last {
                present = true
                let key = String(format: "%d-%d-%.5f-%.5f-%.5f-%.5f", n.previewSelected, r.count, a.lat, a.lon, b.lat, b.lon)
                if key != previewKey {
                    previewKey = key
                    routeShape = nil
                    points = r
                }
            }
        }
        if !present {
            // Sin ruta un rato (navegación terminada): se libera la memoria.
            if route != nil {
                if let since = routeMissingSince {
                    if t - since > 20 { clearRoute() }
                } else {
                    routeMissingSince = t
                }
            }
            return
        }
        routeMissingSince = nil
        if let pts = points {
            let line = RoutePath(points: pts)
            route = line
            routeGeneration += 1
            gapAttempts.removeAll()
            turns = line.turns()
            lock.lock()
            let before = entries.count
            entries = CorridorPlanner.retain(entries, on: line, northUp: s.northUp)
            let after = entries.count
            lock.unlock()
            cancelPrefetch()
            logLine(String(format: "[MAPA] ruta para guardar: %.1f km y %d giros; se conservan %d de %d imágenes", line.length / 1000, turns.count, after, before))
        }
        if n.navigating, let p = pose.progress {
            routeProgress = p
        } else if let line = route {
            let place = line.locate(pose.here)
            routeProgress = place.offset < 250 ? place.along : 0
        }
    }

    private func clearRoute() {
        route = nil
        routeShape = nil
        previewKey = ""
        turns = []
        routeMissingSince = nil
        routeTarget = 0
        cancelPrefetch()
        lock.lock()
        entries.removeAll()
        lock.unlock()
        coverage = CorridorCoverage.Result(continuous: 0, covered: 0, checked: 0, gaps: 0)
        publish(.none)
    }

    private func cancelPrefetch() {
        for p in prefetchers.values { p.snapshotter.cancel() }
        prefetchers.removeAll()
    }

    /// Memoria para el mapa guardado: una parte de la que le queda libre a la app (0.6.3: hasta
    /// 96 MB; eran 64 MB).
    static func memoryBudget() -> Int {
        MapCorridor.budget(available: Int(os_proc_available_memory()))
    }

    /// Pide las imágenes que faltan de la ruta por delante, las más cercanas primero.
    private func prefetch(_ n: HUDSnapshot, _ s: MapSettings, pixels: CGSize, now: Date) {
        guard let route = route, !route.isEmpty else { return }
        let distance = 680 * s.zoom
        let visible = (heightPerDistance[false] ?? 0.62) * distance
        let step = CorridorPlanner.stableStep(current: routeStep, visible: visible)
        if step != routeStep {
            if routeStep > 0 {
                logLine(String(format: "[MAPA] separación del mapa guardado: %.0f m (antes %.0f m)", step, routeStep))
            }
            routeStep = step
        }
        budget = TFTMap.memoryBudget()
        if now.timeIntervalSinceReferenceDate < pressureUntil { budget /= 2 }
        capacity = CorridorPlanner.capacity(budgetBytes: budget, averageBytes: averageBytes, maxImages: TFTMap.maxImages)
        let progress = routeProgress
        lock.lock()
        if entries.count > capacity || (entries.first.map { $0.anchor < progress - 400 } ?? false) {
            entries = CorridorPlanner.trim(entries, progress: progress, capacity: capacity)
        }
        let existing = entries
        lock.unlock()
        routeTarget = CorridorPlanner.horizon(remaining: max(0, route.length - progress), capacity: capacity, step: step)
        let free = TFTMap.parallelPrefetch - prefetchers.count
        guard free > 0, existing.count < capacity else { return }
        guard now.timeIntervalSinceReferenceDate >= pauseUntil else { return }
        let anchors = CorridorPlanner.anchors(route: route, from: progress, to: progress + routeTarget, step: step, turns: turns)
        // Velocidad media prevista, para saber a qué hora se pasa por cada tramo (día o noche).
        let speed = n.remainingTime > 1 ? max(5, n.remainingDistance / n.remainingTime) : 11
        let nightAt: (Double) -> Bool = { anchor in
            let eta = now.addingTimeInterval(max(0, anchor - progress) / speed)
            return DashState.shared.night(at: eta, place: route.point(at: anchor))
        }
        var wanted = CorridorPlanner.missing(
            anchors: anchors, route: route, existing: existing, inFlight: Array(prefetchers.keys),
            night: nightAt, styleKey: { s.styleKey(night: $0) }, northUp: s.northUp, step: step, limit: free
        )
        // 0.6.5: huecos en curvas que la rejilla no ve (el guardado se quedaba parado). Se piden
        // junto con lo demás, siempre lo más cercano primero.
        let fills = CorridorPlanner.gapFills(
            route: route, progress: progress, end: progress + routeTarget, existing: existing,
            inFlight: Array(prefetchers.keys), night: nightAt, styleKey: { s.styleKey(night: $0) },
            northUp: s.northUp, attempts: gapAttempts, limit: free
        )
        if !fills.isEmpty {
            let merged = CorridorPlanner.merge(wanted, fills, limit: free)
            for f in merged where fills.contains(f) {
                gapAttempts[Int(f.anchor / 25), default: 0] += 1
                gapFills += 1
                logLine(String(format: "[MAPA] hueco del mapa guardado a %.1f km (curva): se pide una imagen más", max(0, f.anchor - progress) / 1000))
            }
            wanted = merged
        }
        for r in wanted {
            startPrefetch(r, s: s, distance: distance, pixels: pixels, now: now)
        }
    }

    private func startPrefetch(_ r: CorridorRequest, s: MapSettings, distance: Double, pixels: CGSize, now: Date) {
        let req = makeRequest(here: r.here, heading: r.heading, distance: distance, pitch: 0, night: r.night,
                              pixels: pixels, s: s, now: now, anchor: r.anchor)
        let token = UUID()
        let generation = routeGeneration
        let northUp = s.northUp
        requests += 1
        let snapshotter = snap(req, compress: true) { [weak self] base, error in
            guard let self = self, self.prefetchers[r.anchor]?.token == token else { return }
            self.prefetchers[r.anchor] = nil
            self.finished(base, error: error, req: req)
            guard let base = base else { return }
            self.calibrate(base, req)
            var entry = CorridorEntry(base: base, anchor: r.anchor, ahead: req.center.distance(to: req.here))
            if generation != self.routeGeneration {
                // La ruta cambió mientras llegaba: se sitúa en la nueva o se descarta.
                guard let line = self.route, let kept = CorridorPlanner.retain([entry], on: line, northUp: northUp).first else { return }
                entry = kept
            }
            self.averageBytes = max(20_000, Int(Double(self.averageBytes) * 0.9 + Double(entry.bytes) * 0.1))
            self.lock.lock()
            self.entries.append(entry)
            self.entries.sort { $0.anchor < $1.anchor }
            self.lock.unlock()
        }
        prefetchers[r.anchor] = (snapshotter, now.timeIntervalSinceReferenceDate, token)
    }

    private func updateCoverage(_ s: MapSettings) {
        guard let line = route else {
            coverage = CorridorCoverage.Result(continuous: 0, covered: 0, checked: 0, gaps: 0)
            publish(.none)
            return
        }
        lock.lock()
        let list = entries
        lock.unlock()
        coverage = CorridorCoverage.scan(route: line, from: routeProgress, to: line.length, entries: list, northUp: s.northUp)
        let remaining = max(0, line.length - routeProgress)
        // Con la ruta propuesta todavía sin calcular el horizonte, se usa toda la ruta.
        let horizon = routeTarget > 0 ? routeTarget : remaining + 1
        publish(MapCoverageState.make(routeActive: true, remaining: remaining, continuous: coverage.continuous,
                                      horizon: horizon, cached: list.count, capacity: capacity))
    }

    /// Guarda la cobertura para el dibujo y registra cuando cambia de estado.
    private func publish(_ state: MapCoverageState) {
        lock.lock()
        let old = coverageSummary.kind
        coverageSummary = state
        lock.unlock()
        guard state.kind != old, state.kind != .none else { return }
        logLine("[MAPA] " + state.text)
    }

    // MARK: - Instantánea

    /// Cuenta y registra el resultado de cada petición.
    private func finished(_ base: MapBase?, error: Error?, req: Request) {
        guard let base = base else {
            failureCount += 1
            failures += 1
            lastError = error?.localizedDescription ?? "sin imagen"
            if failures == 1 || failures % 20 == 0 {
                logLine("[MAPA] no llegó la imagen de calles: \(lastError)")
            }
            if req.anchor >= 0 {
                failStreak += 1
                let wait = min(60, pow(2, Double(min(6, failStreak))))
                pauseUntil = Date().timeIntervalSinceReferenceDate + wait
                if failStreak <= 3 || failStreak % 10 == 0 {
                    logLine(String(format: "[MAPA] guardado en pausa %.0f s tras %d fallos seguidos de Apple", wait, failStreak))
                }
            }
            return
        }
        if req.anchor >= 0 {
            if failStreak > 0 { logLine("[MAPA] Apple vuelve a entregar imágenes: sigue el guardado") }
            failStreak = 0
            pauseUntil = 0
        }
        successes += 1
        lastSuccess = Date()
        if Date().timeIntervalSinceReferenceDate - req.time > 5 { late += 1 }
        if failures > 0 || !announced {
            failures = 0
            announced = true
            var detail = ""
            if let a = base.project(req.center), let f = base.project(req.center.moved(50, bearing: req.heading)) {
                let fraction = Double(hypot(a.x - f.x, a.y - f.y))
                if fraction > 0.001 { detail = String(format: " (unos %.0f m de alto en la imagen)", 50 / fraction) }
            }
            logLine("[MAPA] calles de Apple Maps en la moto" + detail)
        }
    }

    private func snap(_ req: Request, compress: Bool = false, done: @escaping (MapBase?, Error?) -> Void) -> MKMapSnapshotter {
        lock.lock()
        let s = settings
        lock.unlock()
        let scale = s.labels.scale
        let o = MKMapSnapshotter.Options()
        o.size = CGSize(width: req.pixels.width / scale, height: req.pixels.height / scale)
        o.scale = scale
        o.camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: req.center.lat, longitude: req.center.lon),
            fromDistance: req.distance, pitch: CGFloat(req.pitch), heading: req.heading
        )
        o.traitCollection = UITraitCollection(userInterfaceStyle: req.night ? .dark : .light)
        if #available(iOS 17.0, *) {
            o.preferredConfiguration = TFTMap.configuration(s)
        } else {
            switch s.style {
            case .standard, .muted: o.mapType = .standard
            case .hybrid: o.mapType = .hybrid
            case .satellite: o.mapType = .satellite
            }
            o.pointOfInterestFilter = TFTMap.places
        }
        let snapshotter = MKMapSnapshotter(options: o)
        let size = o.size
        snapshotter.start(with: queue) { snapshot, error in
            var base: MapBase?
            if let snapshot = snapshot {
                base = TFTMap.makeBase(snapshot, req, size: size, compress: compress)
            }
            DispatchQueue.main.async { done(base, error) }
        }
        return snapshotter
    }

    /// Lugares que se muestran en el mapa: solo los útiles en moto, para no saturarlo.
    static let places = MKPointOfInterestFilter(including: [.gasStation, .parking, .hospital, .police, .evCharger])

    @available(iOS 17.0, *)
    static func configuration(_ s: MapSettings) -> MKMapConfiguration {
        // La vista inclinada usa el relieve "realista" de Apple, que es el que admite inclinación.
        let elevation: MKMapConfiguration.ElevationStyle = s.threeD ? .realistic : .flat
        switch s.style {
        case .standard, .muted:
            let c = MKStandardMapConfiguration(elevationStyle: elevation, emphasisStyle: s.style == .muted ? .muted : .default)
            c.showsTraffic = s.traffic
            c.pointOfInterestFilter = places
            return c
        case .hybrid:
            let c = MKHybridMapConfiguration(elevationStyle: elevation)
            c.showsTraffic = s.traffic
            c.pointOfInterestFilter = places
            return c
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: elevation)
        }
    }

    /// Imagen + proyección. Se toman cuatro puntos del terreno alrededor del centro y se mira
    /// dónde los puso Apple en la imagen: con eso se sitúa cualquier otro punto.
    private static func makeBase(_ snap: MKMapSnapshotter.Snapshot, _ req: Request, size: CGSize, compress: Bool) -> MapBase? {
        guard let cg = snap.image.cgImage else { return nil }
        let span = max(30, req.visibleHeight * 0.18)
        let forward = req.heading
        let corners = [
            req.center.moved(span, bearing: forward).moved(span, bearing: forward + 90),
            req.center.moved(span, bearing: forward).moved(span, bearing: forward - 90),
            req.center.moved(-span, bearing: forward).moved(span, bearing: forward - 90),
            req.center.moved(-span, bearing: forward).moved(span, bearing: forward + 90),
        ]
        var samples: [(GeoPoint, CGPoint)] = []
        for g in corners {
            let p = snap.point(for: CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon))
            samples.append((g, CGPoint(x: p.x / size.width, y: p.y / size.height)))
        }
        var data: Data?
        var image: CGImage? = cg
        if compress {
            data = snap.image.jpegData(compressionQuality: 0.7)
            if data != nil { image = nil }
        }
        return MapBase(
            image: image, data: data, pixelWidth: cg.width, pixelHeight: cg.height,
            center: req.center, heading: req.heading, pitch: req.pitch, night: req.night, live: !compress,
            anchor: req.anchor, created: Date().timeIntervalSinceReferenceDate, styleKey: req.styleKey,
            samples: samples
        )
    }
}
