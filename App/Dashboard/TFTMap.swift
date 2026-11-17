// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mapa de calles para la moto con instantáneas de Apple Maps (MKMapSnapshotter).
//
// Apple solo genera instantáneas con la app en primer plano: si se piden en segundo plano, no
// llegan hasta volver a abrir la app. Por eso:
//  - con la app abierta se piden sin parar, siguiendo la posición (mapa en vivo);
//  - durante una ruta, además, se guardan instantáneas a lo largo del recorrido, para seguir
//    mostrando calles con el iPhone bloqueado;
//  - si no hay ninguna que sirva, el panel vuelve al dibujo simple de la ruta.
import Foundation
import MapKit
import UIKit

final class TFTMap {
    static let shared = TFTMap()

    /// Dónde debe quedar la posición dentro de la imagen (fracción del alto, desde arriba).
    static let puckY = 0.72

    private let queue = DispatchQueue(label: "cfmoto.tftmap", qos: .userInitiated)
    private let lock = NSLock()

    // Lo que lee el hilo de dibujo (protegido por `lock`).
    private var live: MapBase?
    private var cache: [MapBase] = []
    private var inUse: MapBase?
    private var settings = MapSettings()

    // Lo demás solo se toca desde el hilo principal.
    private var timer: Timer?
    private var liveSnapshotter: MKMapSnapshotter?
    private var cacheSnapshotter: MKMapSnapshotter?
    private var lastLive: Request?
    private var routeKey: ObjectIdentifier?
    private var cachedUpTo = 0.0
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
    }

    func configure(_ s: MapSettings) {
        lock.lock()
        let changed = s != settings
        settings = s
        if changed {
            live = nil
            cache.removeAll()
            inUse = nil
        }
        lock.unlock()
        if changed {
            lastLive = nil
            cachedUpTo = 0
            routeKey = nil
        }
    }

    // MARK: - Lo que usa el dibujo (cualquier hilo)

    /// La imagen de calles que mejor encaja con la posición actual, o nil.
    func base(for n: HUDSnapshot, now: Date) -> MapBase? {
        guard let pose = MapPose.of(n, now: now) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard settings.streets else { return nil }
        let t = now.timeIntervalSinceReferenceDate
        func spot(_ b: MapBase) -> CGPoint? { b.project(pose.here) }
        if let l = live, t - l.created < 30, let q = spot(l), q.x > 0.06, q.x < 0.94, q.y > 0.22, q.y < 0.96 {
            return use(l)
        }
        // Guardadas a lo largo de la ruta (iPhone bloqueado o app en segundo plano).
        var best: MapBase?
        var score = Double.greatestFiniteMagnitude
        if let progress = pose.progress {
            for c in cache where abs(c.anchor - progress) < 3000 {
                guard let q = spot(c), q.x > 0.1, q.x < 0.9, q.y > 0.3, q.y < 0.94 else { continue }
                var turn = abs(c.heading - pose.heading).truncatingRemainder(dividingBy: 360)
                if turn > 180 { turn = 360 - turn }
                guard pose.heading < 0 || turn < 55 else { continue }
                let value = abs(Double(q.y) - TFTMap.puckY) + turn / 90
                if value < score {
                    score = value
                    best = c
                }
            }
        }
        if let b = best { return use(b) }
        // La última en vivo, aunque sea vieja, mientras la posición siga dentro.
        if let l = live, let q = spot(l), q.x > 0.02, q.x < 0.98, q.y > 0.04, q.y < 0.99 {
            return use(l)
        }
        return nil
    }

    /// Solo una imagen guardada queda descomprimida a la vez (memoria en segundo plano).
    private func use(_ b: MapBase) -> MapBase {
        if inUse !== b {
            if let old = inUse, !old.live { old.releaseDecoded() }
            inUse = b
        }
        return b
    }

    // MARK: - Peticiones (hilo principal)

    private func tick() {
        guard UIApplication.shared.applicationState == .active else { return }
        lock.lock()
        let s = settings
        lock.unlock()
        guard s.streets else { return }
        let layout = DashState.shared.currentLayout()
        guard layout.showsMap else { return }
        let n = HUDState.shared.get()
        let now = Date()
        guard let pose = MapPose.of(n, now: now) else { return }
        let night = DashState.shared.isNight(n.style)
        let rect = DashLayoutEngine.mapRect(layout, width: 800, height: 400, reservedBottom: HUDRenderer.reservedBottom)
            ?? CGRect(x: 0, y: 0, width: 800, height: 400)
        let pixels = CGSize(width: max(200, (rect.width / 2).rounded() * 2), height: max(120, (rect.height / 2).rounded() * 2))

        if liveSnapshotter == nil {
            // Con ruta, la imagen se pide para el punto de la ruta donde estará la moto cuando
            // llegue (posición y rumbo de ese punto): así el mapa no gira tarde en las curvas.
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
        if liveSnapshotter == nil && cacheSnapshotter == nil {
            prefetch(n, pose, s, night: night, pixels: pixels, now: now)
        }
    }

    /// Distancia de la cámara: más lejos cuanto más rápido, más cerca antes de un giro.
    private func cameraDistance(_ pose: MapPose, _ s: MapSettings) -> Double {
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
            var turn = abs(last.heading - req.heading).truncatingRemainder(dividingBy: 360)
            if turn > 180 { turn = 360 - turn }
            let zoom = abs(last.distance - req.distance) / max(1, last.distance)
            let stale = last.styleKey != req.styleKey || last.pixels != req.pixels || last.pitch != req.pitch
            let needed = stale || age > 6 || moved > max(6, last.visibleHeight * 0.04) || turn > 5 || zoom > 0.1
            guard needed, age > 0.35 || stale else { return }
        }
        lastLive = req
        liveSnapshotter = snap(req) { [weak self] base in
            guard let self = self else { return }
            self.liveSnapshotter = nil
            guard let base = base else { return }
            let took = Date().timeIntervalSinceReferenceDate - req.time
            if took > 0 && took < 10 { self.latency = self.latency * 0.7 + took * 0.3 }
            if req.pitch > 0 && !self.told3D {
                self.told3D = true
                logLine(base.perspective > 0.02
                        ? "[MAPA] vista inclinada (3D) aplicada"
                        : "[MAPA] Apple entregó el mapa plano aunque se pidió inclinado")
            }
            self.calibrate(base, req)
            self.lock.lock()
            self.live = base
            self.lock.unlock()
        }
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

    /// Guarda instantáneas planas a lo largo de la ruta, por delante de la moto.
    private func prefetch(_ n: HUDSnapshot, _ pose: MapPose, _ s: MapSettings, night: Bool, pixels: CGSize, now: Date) {
        guard n.navigating, let shape = n.shape, let geo = n.geo, let progress = pose.progress else {
            if routeKey != nil {
                routeKey = nil
                lock.lock()
                cache.removeAll()
                lock.unlock()
            }
            return
        }
        let key = ObjectIdentifier(shape)
        lock.lock()
        if key != routeKey {
            cache.removeAll()
        }
        cache.removeAll { $0.anchor < progress - 500 || $0.styleKey != s.styleKey(night: night) }
        let count = cache.count
        lock.unlock()
        if key != routeKey {
            routeKey = key
            cachedUpTo = progress
        }
        cachedUpTo = max(cachedUpTo, progress - 50)
        guard count < 40, cachedUpTo < min(shape.length, progress + 8000) else { return }

        let distance = 680 * s.zoom
        let visible = (heightPerDistance[false] ?? 0.62) * distance
        // La moto entra por abajo y recorre la imagen hacia arriba: una instantánea cada ~45 %.
        let at = min(shape.length, cachedUpTo + visible * 0.1)
        var heading = shape.bearing(at: min(shape.length, at + visible * 0.25), span: 60) * 180 / .pi
        if heading < 0 { heading += 360 }
        let here = geo.geo(shape.point(at: at))
        let req = makeRequest(here: here, heading: s.northUp ? 0 : heading, distance: distance, pitch: 0, night: night,
                              pixels: pixels, s: s, now: now, anchor: at)
        let next = at + visible * 0.45
        cacheSnapshotter = snap(req, compress: true) { [weak self] base in
            guard let self = self else { return }
            self.cacheSnapshotter = nil
            guard let base = base else { return }
            self.cachedUpTo = max(self.cachedUpTo, next)
            self.lock.lock()
            self.cache.append(base)
            self.cache.sort { $0.anchor < $1.anchor }
            self.lock.unlock()
        }
    }

    // MARK: - Instantánea

    private func snap(_ req: Request, compress: Bool = false, done: @escaping (MapBase?) -> Void) -> MKMapSnapshotter {
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
        snapshotter.start(with: queue) { [weak self] snapshot, error in
            var base: MapBase?
            if let snapshot = snapshot {
                base = TFTMap.makeBase(snapshot, req, size: size, compress: compress)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if base == nil {
                    self.failures += 1
                    self.lastError = error?.localizedDescription ?? "sin imagen"
                    if self.failures == 1 || self.failures % 20 == 0 {
                        logLine("[MAPA] no llegó la imagen de calles: \(self.lastError)")
                    }
                } else if self.failures > 0 || !self.announced {
                    self.failures = 0
                    self.announced = true
                    var detail = ""
                    if let b = base, let a = b.project(req.center), let f = b.project(req.center.moved(50, bearing: req.heading)) {
                        let fraction = Double(hypot(a.x - f.x, a.y - f.y))
                        if fraction > 0.001 { detail = String(format: " (unos %.0f m de alto en la imagen)", 50 / fraction) }
                    }
                    logLine("[MAPA] calles de Apple Maps en la moto" + detail)
                }
                done(base)
            }
        }
        return snapshotter
    }

    private var announced = false

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
            data = snap.image.jpegData(compressionQuality: 0.72)
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
