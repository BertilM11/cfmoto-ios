// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import MapKit
import CoreLocation
import Combine
import UIKit

/// Lo que la interfaz necesita saber de la guía en cada momento.
struct Guidance {
    var tick = 0
    var kind: ManeuverKind = .straight
    var distance: Double = 0
    var text: String = ""
    var thenKind: ManeuverKind?
    var remainingDistance: Double = 0
    var remainingTime: TimeInterval = 0
    var eta = Date()
    var fraction: Double = 0
    var rerouting = false
    var offRoute = false
    var speed: Double = 0
    /// Posición ajustada a la ruta (o la del GPS si se salió de ella).
    var snapped: CLLocationCoordinate2D?
    /// Rumbo de la ruta en la posición actual, en grados.
    var bearing: Double = 0
}

/// Motor de navegación: calcula rutas reales con Apple Maps, sigue la posición sobre la ruta,
/// anuncia las maniobras, recalcula al desviarse y mantiene al día la pantalla de la moto.
final class NavEngine: ObservableObject {
    static let shared = NavEngine()

    enum Phase {
        case idle
        case planning
        case preview
        case navigating
        case arrived
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var routes: [MKRoute] = []
    @Published private(set) var selectedIndex = 0
    /// Cambia cuando cambian las rutas o la elegida, para que el mapa las redibuje.
    @Published private(set) var routesVersion = 0
    @Published private(set) var destinationName = ""
    @Published private(set) var destinationCoordinate: CLLocationCoordinate2D?
    @Published private(set) var message: String?
    @Published private(set) var guidance = Guidance()
    @Published private(set) var simulating = false
    @Published var voiceMuted = false {
        didSet { voice.muted = voiceMuted }
    }

    /// Estilo de la pantalla de la moto (sigue al tema de la app).
    var hudStyle: HUDStyle = .night {
        didSet { pushHUD() }
    }

    /// Enlace con la moto activo: la app debe seguir viva en segundo plano.
    var linkActive = false {
        didSet { refreshDriving() }
    }

    private(set) var guided: GuidedRoute?

    private var destinationItem: MKMapItem?
    private var directions: MKDirections?
    private var pendingPlan = false
    private let voice = VoiceGuide()
    private var cancellables = Set<AnyCancellable>()

    // Estado de la guía
    private var lastSegment = 0
    private var progress = 0.0
    private var offCount = 0
    private var wrongWayCount = 0
    private var rerouting = false
    private var lastReroute = Date.distantPast
    private var spoken: [Int: Int] = [:]
    private var fixTime: TimeInterval = 0

    // Simulación
    private var simulationTimer: Timer?
    private var simulationDistance = 0.0
    private var simulationSpeed = 14.0

    private var idleTimer: Timer?

    private init() {
        LocationService.shared.$last
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in self?.onFix(location) }
            .store(in: &cancellables)
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.phase != .navigating { self.pushHUD() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: - Planificación

    func plan(to item: MKMapItem) {
        guard phase != .navigating else { return }
        destinationItem = item
        destinationName = item.name ?? "Destino"
        destinationCoordinate = item.placemark.coordinate
        message = nil
        guard let here = LocationService.shared.last else {
            pendingPlan = true
            phase = .planning
            message = "Buscando tu ubicación…"
            return
        }
        calculate(from: here.coordinate, reroute: false)
    }

    func plan(toCoordinate coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        plan(to: item)
    }

    func select(_ index: Int) {
        guard phase == .preview, routes.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        routesVersion += 1
        pushHUD()
    }

    /// Cancela la vista previa o termina la navegación y vuelve al mapa.
    func cancel() {
        directions?.cancel()
        directions = nil
        pendingPlan = false
        stopSimulationTimer()
        simulating = false
        voice.stop()
        guided = nil
        rerouting = false
        startAlternates = []
        routes = []
        selectedIndex = 0
        routesVersion += 1
        destinationItem = nil
        destinationName = ""
        destinationCoordinate = nil
        message = nil
        guidance = Guidance()
        phase = .idle
        refreshDriving()
        pushHUD()
    }

    private func calculate(from origin: CLLocationCoordinate2D, reroute: Bool) {
        guard let destination = destinationItem else { return }
        directions?.cancel()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = !reroute
        let d = MKDirections(request: request)
        directions = d
        if !reroute {
            phase = .planning
            message = nil
        }
        d.calculate { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self, self.directions === d else { return }
                self.directions = nil
                if let found = response?.routes, !found.isEmpty {
                    if reroute {
                        self.applyReroute(found[0])
                    } else {
                        self.applyPreview(found)
                    }
                    return
                }
                let reason = error?.localizedDescription ?? "sin respuesta"
                logLine("[RUTA] no se pudo calcular: \(reason)")
                if reroute {
                    self.rerouting = false
                    self.guidance.rerouting = false
                    self.pushHUD()
                } else {
                    self.routes = []
                    self.routesVersion += 1
                    self.phase = .idle
                    self.message = "No se pudo calcular la ruta. Revisa la conexión e inténtalo de nuevo."
                }
            }
        }
    }

    private func applyPreview(_ found: [MKRoute]) {
        routes = Array(found.prefix(3))
        selectedIndex = 0
        routesVersion += 1
        message = nil
        phase = .preview
        let summary = routes.map { "\(Int($0.distance)) m/\(Int($0.expectedTravelTime / 60)) min" }.joined(separator: ", ")
        logLine("[RUTA] \(routes.count) ruta(s) a «\(destinationName)»: \(summary)")
    }

    private func applyReroute(_ route: MKRoute) {
        guard phase == .navigating else { return }
        routes = [route]
        selectedIndex = 0
        routesVersion += 1
        startGuidance(route)
        rerouting = false
        logLine("[RUTA] ruta recalculada: \(Int(route.distance)) m")
        if let location = LocationService.shared.last {
            process(location)
        }
    }

    // MARK: - Navegación

    func startNavigation() {
        begin(simulated: false, speed: 0, skipToFirstTurn: false)
    }

    /// Recorre la ruta con una posición inventada, para probar sin moverse. La interfaz y la
    /// pantalla de la moto lo marcan como SIMULACIÓN.
    func startSimulation(speed: Double = 14, skipToFirstTurn: Bool = false) {
        begin(simulated: true, speed: speed, skipToFirstTurn: skipToFirstTurn)
    }

    private func begin(simulated: Bool, speed: Double, skipToFirstTurn: Bool) {
        guard phase == .preview, routes.indices.contains(selectedIndex) else { return }
        let route = routes[selectedIndex]
        // Las otras rutas propuestas se siguen viendo en la moto al empezar, como referencia.
        startAlternates = routes.enumerated().filter { $0.offset != selectedIndex }.map { $0.element }
        routes = [route]
        selectedIndex = 0
        routesVersion += 1
        simulating = simulated
        startGuidance(route)
        phase = .navigating
        refreshDriving()
        voice.say(simulated ? "Simulación de recorrido iniciada" : "Ruta iniciada")

        if simulated {
            simulationSpeed = max(1, speed)
            simulationDistance = 0
            if skipToFirstTurn, let g = guided,
               let first = g.maneuvers.first(where: { $0.at > 420 && $0.kind != .arrive }) {
                simulationDistance = first.at - 260
            }
            stopSimulationTimer()
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.simulationStep(0.5) }
            RunLoop.main.add(timer, forMode: .common)
            simulationTimer = timer
            simulationStep(0)
        } else if let location = LocationService.shared.last {
            process(location)
        }
    }

    private func startGuidance(_ route: MKRoute) {
        let g = GuidedRoute(route: route)
        guided = g
        lastSegment = 0
        progress = 0
        offCount = 0
        wrongWayCount = 0
        spoken = [:]
        logLine("[RUTA] guía lista: \(Int(g.shape.length)) m, \(g.maneuvers.count) maniobras, textos al \(g.convention)")
        for (i, step) in route.steps.prefix(12).enumerated() {
            logLine("[RUTA] paso \(i): \(Int(step.distance)) m «\(step.instructions)»")
        }
        for (i, m) in g.maneuvers.prefix(12).enumerated() {
            logLine("[RUTA] maniobra \(i): a \(Int(m.at)) m, tipo \(m.kind), «\(m.text)»")
        }
    }

    private func onFix(_ location: CLLocation) {
        if pendingPlan, phase == .planning {
            pendingPlan = false
            calculate(from: location.coordinate, reroute: false)
            return
        }
        if phase == .navigating && !simulating {
            process(location)
        }
    }

    private func simulationStep(_ dt: Double) {
        guard phase == .navigating, simulating, let g = guided else {
            stopSimulationTimer()
            return
        }
        simulationDistance = min(g.shape.length, simulationDistance + simulationSpeed * dt)
        let point = g.shape.point(at: simulationDistance)
        var course = g.shape.bearing(at: simulationDistance) * 180 / .pi
        if course < 0 { course += 360 }
        let location = CLLocation(
            coordinate: g.coordinate(point),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            speed: simulationSpeed,
            timestamp: Date()
        )
        process(location)
    }

    private func stopSimulationTimer() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    /// Un fijo nuevo (real o simulado) mientras se navega.
    private func process(_ location: CLLocation) {
        guard let g = guided else { return }
        let snap = g.snap(g.local(location.coordinate), hint: lastSegment, lastProgress: progress)
        let speed = max(0, location.speed)
        let accuracy = max(0, location.horizontalAccuracy)
        let limit = max(45, min(90, accuracy * 2))
        var off = snap.lateral > limit

        // ¿Circula en sentido contrario al de la ruta?
        if !off, speed > 4, location.course >= 0 {
            var routeCourse = g.shape.bearing(at: snap.along) * 180 / .pi
            if routeCourse < 0 { routeCourse += 360 }
            var difference = abs(location.course - routeCourse)
            if difference > 180 { difference = 360 - difference }
            wrongWayCount = difference > 120 ? wrongWayCount + 1 : 0
            if wrongWayCount >= 6 { off = true }
        } else if speed <= 4 {
            wrongWayCount = 0
        }

        if off {
            if accuracy <= 65 { offCount += 1 }
        } else {
            offCount = 0
            lastSegment = snap.segment
            progress = snap.along
        }
        if offCount >= 4 && !simulating {
            requestReroute(from: location)
        }
        publish(g, location: location, speed: speed, off: off)
    }

    private func publish(_ g: GuidedRoute, location: CLLocation, speed: Double, off: Bool) {
        let length = max(1, g.shape.length)
        let remaining = max(0, length - progress)
        let ratio = remaining / length
        let lastIndex = g.maneuvers.count - 1
        guard lastIndex >= 0 else { return }
        let index = g.maneuvers.firstIndex { $0.at >= progress - 12 } ?? lastIndex
        let maneuver = g.maneuvers[index]
        let distance = max(0, maneuver.at - progress)
        var then: ManeuverKind?
        if index < lastIndex, g.maneuvers[index + 1].at - maneuver.at < 170 {
            then = g.maneuvers[index + 1].kind
        }

        var bearing = g.shape.bearing(at: progress, span: 18) * 180 / .pi
        if bearing < 0 { bearing += 360 }

        var next = guidance
        next.tick += 1
        next.kind = maneuver.kind
        next.distance = distance
        next.text = maneuver.text
        next.thenKind = then
        next.remainingDistance = g.route.distance * ratio
        next.remainingTime = g.route.expectedTravelTime * ratio
        next.eta = Date().addingTimeInterval(next.remainingTime)
        next.fraction = 1 - ratio
        next.rerouting = rerouting
        next.offRoute = off
        next.speed = speed
        next.bearing = bearing
        next.snapped = off ? location.coordinate : g.coordinate(g.shape.point(at: progress))
        guidance = next
        fixTime = Date().timeIntervalSinceReferenceDate
        pushHUD()

        if !off {
            announce(g, index: index, distance: distance, speed: speed)
        }
        if index == lastIndex && remaining < 30 {
            arrive()
        }
    }

    private func arrive() {
        guard phase == .navigating else { return }
        stopSimulationTimer()
        phase = .arrived
        voice.say("Has llegado a tu destino")
        logLine("[RUTA] llegada a «\(destinationName)»")
        refreshDriving()
        pushHUD()
    }

    private func requestReroute(from location: CLLocation) {
        guard !rerouting, Date().timeIntervalSince(lastReroute) > 8 else { return }
        rerouting = true
        lastReroute = Date()
        offCount = 0
        wrongWayCount = 0
        logLine("[RUTA] fuera de la ruta: recalculando")
        voice.say("Recalculando la ruta")
        calculate(from: location.coordinate, reroute: true)
    }

    // MARK: - Voz

    private func announce(_ g: GuidedRoute, index: Int, distance: Double, speed: Double) {
        let maneuver = g.maneuvers[index]
        var bits = spoken[index] ?? 0
        let nowAt = max(40, speed * 3.5)
        let soonAt = max(260, speed * 15)
        let previous = index > 0 ? g.maneuvers[index - 1].at : 0
        let leg = maneuver.at - previous
        let arriving = maneuver.kind == .arrive

        if distance <= nowAt {
            if bits & 4 == 0 {
                bits |= 15
                if !arriving { voice.say(maneuver.text) }
            }
        } else if distance <= soonAt {
            if bits & 2 == 0 {
                bits |= 11
                let what = arriving ? "llegarás a tu destino" : NavEngine.lowerFirst(maneuver.text)
                voice.say("En \(NavEngine.spokenDistance(distance)), \(what)")
            }
        } else if distance <= 1100 && leg > 2000 {
            if bits & 1 == 0 {
                bits |= 9
                let what = arriving ? "llegarás a tu destino" : NavEngine.lowerFirst(maneuver.text)
                voice.say("En un kilómetro, \(what)")
            }
        } else if distance > 900 {
            if bits & 8 == 0 {
                bits |= 8
                voice.say("Continúa \(NavEngine.spokenDistance(distance))")
            }
        }
        spoken[index] = bits
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func spokenDistance(_ meters: Double) -> String {
        if meters >= 950 {
            let km = (meters / 100).rounded() / 10
            if km == km.rounded() {
                let whole = Int(km)
                return whole == 1 ? "un kilómetro" : "\(whole) kilómetros"
            }
            return String(format: "%.1f kilómetros", km)
        }
        let rounded = max(50, Int((meters / 50).rounded()) * 50)
        return "\(rounded) metros"
    }

    // MARK: - Segundo plano y pantalla de la moto

    private func refreshDriving() {
        let active = phase == .navigating || linkActive
        LocationService.shared.setDriving(active)
        UIApplication.shared.isIdleTimerDisabled = active
    }

    /// Rutas que no se eligieron al empezar (se muestran en gris los primeros metros).
    private var startAlternates: [MKRoute] = []
    /// Rutas alternativas en metros locales de la ruta elegida (se recalculan si cambian).
    private var alternateCache: (version: Int, routes: [[CGPoint]]) = (-1, [])
    /// Rutas propuestas en coordenadas, para la vista previa en la moto.
    private var previewCache: (version: Int, routes: [[GeoPoint]]) = (-1, [])

    private func alternates(for g: GuidedRoute) -> [[CGPoint]] {
        if alternateCache.version == routesVersion { return alternateCache.routes }
        var out: [[CGPoint]] = []
        for r in startAlternates where r !== g.route {
            let c = GuidedRoute.coordinates(of: r.polyline)
            let step = max(1, c.count / 400)
            out.append(stride(from: 0, to: c.count, by: step).map { g.local(c[$0]) })
        }
        alternateCache = (routesVersion, out)
        return out
    }

    private func previewRoutes() -> [[GeoPoint]] {
        if previewCache.version == routesVersion { return previewCache.routes }
        let out: [[GeoPoint]] = routes.map { r in
            let c = GuidedRoute.coordinates(of: r.polyline)
            let step = max(1, c.count / 500)
            return stride(from: 0, to: c.count, by: step).map { GeoPoint(lat: c[$0].latitude, lon: c[$0].longitude) }
                + (c.last.map { [GeoPoint(lat: $0.latitude, lon: $0.longitude)] } ?? [])
        }
        previewCache = (routesVersion, out)
        return out
    }

    private func pushHUD() {
        var s = HUDSnapshot()
        s.style = hudStyle
        s.destinationName = destinationName
        if simulating {
            s.gpsOk = true
        } else if let last = LocationService.shared.last {
            s.gpsOk = abs(last.timestamp.timeIntervalSinceNow) < 6
        }
        if let last = LocationService.shared.last {
            s.here = GeoPoint(lat: last.coordinate.latitude, lon: last.coordinate.longitude)
            s.course = last.course
            s.speed = max(0, last.speed)
        }
        if phase == .arrived {
            s.arrived = true
        } else if phase == .navigating, let g = guided {
            let current = guidance
            s.navigating = true
            s.rerouting = current.rerouting
            s.simulated = simulating
            s.kind = current.kind
            s.distanceToManeuver = current.distance
            s.instruction = current.text
            s.thenKind = current.thenKind
            s.remainingDistance = current.remainingDistance
            s.remainingTime = current.remainingTime
            s.eta = current.eta
            s.fraction = current.fraction
            s.shape = g.shape
            s.progress = progress
            s.maneuverAt = progress + current.distance
            s.speed = current.offRoute ? 0 : current.speed
            s.fixTime = fixTime
            s.geo = g.geoFrame
            s.course = current.bearing
            if let snapped = current.snapped {
                s.here = GeoPoint(lat: snapped.latitude, lon: snapped.longitude)
            }
            // Las alternativas solo al empezar, como referencia; después distraen.
            if progress < 600 { s.alternates = alternates(for: g) }
        } else if phase == .preview && !routes.isEmpty {
            s.previewRoutes = previewRoutes()
            s.previewSelected = selectedIndex
            s.previewDistances = routes.map { $0.distance }
            s.previewTimes = routes.map { $0.expectedTravelTime }
        }
        HUDState.shared.set(s)
    }
}
