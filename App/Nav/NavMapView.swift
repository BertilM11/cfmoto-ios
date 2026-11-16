// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import MapKit
import Combine

/// Línea de una ruta sobre el mapa.
final class RouteLine: MKPolyline {
    enum Role {
        case casing
        case main
        case alternate
    }

    var role: Role = .main
    var routeIndex = 0
}

/// Marca de posición durante la navegación (ajustada a la ruta).
final class PuckAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

final class DestinationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(coordinate: CLLocationCoordinate2D, title: String) {
        self.coordinate = coordinate
        self.title = title
    }
}

/// Mapa de Apple (MapKit) con las rutas, el destino y la cámara de navegación.
struct NavMapView: UIViewRepresentable {
    @ObservedObject var engine: NavEngine
    let palette: Palette
    @Binding var following: Bool
    let recenterToken: Int
    let bottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = true
        map.isRotateEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        press.minimumPressDuration = 0.55
        map.addGestureRecognizer(press)

        context.coordinator.attach(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NavMapView
        private weak var map: MKMapView?

        private var themeKey = ""
        private var shownVersion = -1
        private var shownNavigating = false
        private var seenRecenter = 0
        private var seenTick = -1
        private var centeredOnce = false
        private var puck: PuckAnnotation?
        private var destination: DestinationAnnotation?
        private var fixSubscription: AnyCancellable?

        init(_ parent: NavMapView) {
            self.parent = parent
            super.init()
        }

        func attach(_ map: MKMapView) {
            self.map = map
            seenRecenter = parent.recenterToken
            // Centrar en la primera ubicación que llegue.
            fixSubscription = LocationService.shared.$last
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] location in self?.firstFix(location) }
        }

        private func firstFix(_ location: CLLocation) {
            guard let map = map, !centeredOnce else {
                fixSubscription = nil
                return
            }
            let phase = parent.engine.phase
            if phase == .idle || phase == .planning {
                centeredOnce = true
                map.setRegion(
                    MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1800, longitudinalMeters: 1800),
                    animated: false
                )
            }
            fixSubscription = nil
        }

        // MARK: - Sincronización con el estado

        func sync(_ map: MKMapView) {
            let engine = parent.engine
            let navigating = engine.phase == .navigating || engine.phase == .arrived

            applyTheme(map, navigating: navigating)
            let margins = UIEdgeInsets(top: 0, left: 0, bottom: parent.bottomInset, right: 0)
            if map.layoutMargins != margins {
                map.layoutMargins = margins
            }

            if shownVersion != engine.routesVersion || shownNavigating != navigating {
                let wasNavigating = shownNavigating
                shownVersion = engine.routesVersion
                shownNavigating = navigating
                rebuildOverlays(map, navigating: navigating)
                if engine.phase == .preview {
                    fitRoutes(map)
                }
                if wasNavigating && !navigating {
                    leaveNavigation(map)
                }
            }
            syncDestination(map)
            syncPuck(map, navigating: navigating)

            if navigating {
                if parent.recenterToken != seenRecenter {
                    seenRecenter = parent.recenterToken
                    seenTick = engine.guidance.tick
                    follow(map, duration: 0.6)
                } else if parent.following, engine.guidance.tick != seenTick {
                    let first = seenTick < 0
                    seenTick = engine.guidance.tick
                    follow(map, duration: first ? 0.8 : 1.05)
                } else if !parent.following, engine.guidance.tick != seenTick {
                    seenTick = engine.guidance.tick
                    movePuckOnly(map)
                }
            } else {
                seenTick = -1
                if parent.recenterToken != seenRecenter {
                    seenRecenter = parent.recenterToken
                    if let c = LocationService.shared.last?.coordinate {
                        map.setCamera(MKMapCamera(lookingAtCenter: c, fromDistance: 2200, pitch: 0, heading: 0), animated: true)
                    }
                }
            }
        }

        private func applyTheme(_ map: MKMapView, navigating: Bool) {
            let p = parent.palette
            let key = "\(p.id)-\(navigating)"
            guard key != themeKey else { return }
            themeKey = key
            map.overrideUserInterfaceStyle = p.mapStyle
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: p.mutedMap ? .muted : .default)
            configuration.showsTraffic = true
            configuration.pointOfInterestFilter = navigating
                ? MKPointOfInterestFilter(including: [.gasStation, .hospital, .police])
                : .includingAll
            map.preferredConfiguration = configuration
            for overlay in map.overlays {
                if let line = overlay as? RouteLine, let renderer = map.renderer(for: overlay) as? MKPolylineRenderer {
                    style(renderer, line)
                    renderer.setNeedsDisplay()
                }
            }
        }

        private func style(_ renderer: MKPolylineRenderer, _ line: RouteLine) {
            let p = parent.palette
            renderer.lineCap = .round
            renderer.lineJoin = .round
            switch line.role {
            case .casing:
                renderer.strokeColor = p.routeCasing
                renderer.lineWidth = 11
            case .main:
                renderer.strokeColor = p.route
                renderer.lineWidth = 7
            case .alternate:
                renderer.strokeColor = p.routeAlternate.withAlphaComponent(0.85)
                renderer.lineWidth = 6
            }
        }

        private func rebuildOverlays(_ map: MKMapView, navigating: Bool) {
            map.removeOverlays(map.overlays.filter { $0 is RouteLine })
            let routes = parent.engine.routes
            guard !routes.isEmpty else { return }
            let selected = min(parent.engine.selectedIndex, routes.count - 1)

            func line(_ route: MKRoute, _ role: RouteLine.Role, _ index: Int) -> RouteLine {
                let l = RouteLine(points: route.polyline.points(), count: route.polyline.pointCount)
                l.role = role
                l.routeIndex = index
                return l
            }
            if !navigating {
                for (i, route) in routes.enumerated() where i != selected {
                    map.addOverlay(line(route, .alternate, i), level: .aboveRoads)
                }
            }
            map.addOverlay(line(routes[selected], .casing, selected), level: .aboveRoads)
            map.addOverlay(line(routes[selected], .main, selected), level: .aboveRoads)
        }

        private func fitRoutes(_ map: MKMapView) {
            let routes = parent.engine.routes
            guard let first = routes.first else { return }
            var rect = first.polyline.boundingMapRect
            for route in routes.dropFirst() {
                rect = rect.union(route.polyline.boundingMapRect)
            }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 150, left: 50, bottom: 50, right: 70), animated: true)
        }

        private func leaveNavigation(_ map: MKMapView) {
            if let c = LocationService.shared.last?.coordinate ?? parent.engine.guidance.snapped {
                map.setCamera(MKMapCamera(lookingAtCenter: c, fromDistance: 2200, pitch: 0, heading: 0), animated: true)
            }
        }

        private func syncDestination(_ map: MKMapView) {
            let target = parent.engine.destinationCoordinate
            if let d = destination {
                if let t = target, abs(t.latitude - d.coordinate.latitude) < 1e-7, abs(t.longitude - d.coordinate.longitude) < 1e-7 {
                    return
                }
                map.removeAnnotation(d)
                destination = nil
            }
            if let t = target {
                let annotation = DestinationAnnotation(coordinate: t, title: parent.engine.destinationName)
                destination = annotation
                map.addAnnotation(annotation)
            }
        }

        private func syncPuck(_ map: MKMapView, navigating: Bool) {
            if navigating {
                if map.showsUserLocation { map.showsUserLocation = false }
                if puck == nil, let c = parent.engine.guidance.snapped ?? LocationService.shared.last?.coordinate {
                    let annotation = PuckAnnotation(coordinate: c)
                    puck = annotation
                    map.addAnnotation(annotation)
                }
            } else {
                if !map.showsUserLocation { map.showsUserLocation = true }
                if let annotation = puck {
                    map.removeAnnotation(annotation)
                    puck = nil
                }
            }
        }

        // MARK: - Cámara de navegación

        private static func offset(_ c: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
            let rad = bearing * .pi / 180
            let dLat = cos(rad) * meters / 110_574
            let dLon = sin(rad) * meters / (111_320 * max(0.1, cos(c.latitude * .pi / 180)))
            return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
        }

        /// Cámara inclinada que mira en el sentido de la marcha, con la posición en el tercio inferior.
        private func follow(_ map: MKMapView, duration: Double) {
            let g = parent.engine.guidance
            guard let position = g.snapped else { return }
            let distance = min(1100, max(420, 420 + g.speed * 22))
            let center = Coordinator.offset(position, meters: distance * 0.24, bearing: g.bearing)
            let camera = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 55, heading: g.bearing)
            let puck = self.puck
            let puckView = puck.flatMap { map.view(for: $0) }
            UIView.animate(
                withDuration: duration, delay: 0,
                options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState],
                animations: {
                    map.camera = camera
                    puck?.coordinate = position
                    puckView?.transform = .identity
                }
            )
        }

        /// Sin seguimiento (el usuario movió el mapa): mover solo la marca y orientarla.
        private func movePuckOnly(_ map: MKMapView) {
            let g = parent.engine.guidance
            guard let position = g.snapped, let puck = puck else { return }
            let angle = (g.bearing - map.camera.heading) * .pi / 180
            UIView.animate(withDuration: 1.0, delay: 0, options: [.curveLinear, .allowUserInteraction]) {
                puck.coordinate = position
                map.view(for: puck)?.transform = CGAffineTransform(rotationAngle: CGFloat(angle))
            }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? RouteLine {
                let renderer = MKPolylineRenderer(polyline: line)
                style(renderer, line)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is PuckAnnotation {
                let id = "puck"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.image = Coordinator.puckImage(parent.palette)
                view.canShowCallout = false
                view.displayPriority = .required
                view.zPriority = .max
                return view
            }
            if annotation is DestinationAnnotation {
                let id = "destination"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.markerTintColor = UIColor(parent.palette.danger)
                view.glyphImage = UIImage(systemName: "flag.fill")
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Si el cambio lo provoca un gesto del usuario, dejar de seguir la posición.
            guard parent.following, shownNavigating else { return }
            let recognizers = mapView.subviews.first?.gestureRecognizers ?? []
            let touching = recognizers.contains { $0.state == .began || $0.state == .changed || $0.state == .ended }
            if touching {
                let binding = parent.$following
                DispatchQueue.main.async { binding.wrappedValue = false }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if shownNavigating && !parent.following {
                movePuckOnly(mapView)
            }
        }

        private static var puckCache: [String: UIImage] = [:]

        private static func puckImage(_ palette: Palette) -> UIImage {
            if let cached = puckCache[palette.id] { return cached }
            let size = CGSize(width: 46, height: 46)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                let ctx = context.cgContext
                ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 38, height: 38))
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                ctx.setFillColor(UIColor(palette.accent).cgColor)
                ctx.fillEllipse(in: CGRect(x: 8, y: 8, width: 30, height: 30))
                ctx.setFillColor(UIColor(palette.onAccent).cgColor)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 23, y: 13))
                ctx.addLine(to: CGPoint(x: 31, y: 31))
                ctx.addLine(to: CGPoint(x: 23, y: 27))
                ctx.addLine(to: CGPoint(x: 15, y: 31))
                ctx.closePath()
                ctx.fillPath()
            }
            puckCache[palette.id] = image
            return image
        }

        // MARK: - Gestos

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        private static func distance(from p: MKMapPoint, to polyline: MKPolyline) -> Double {
            let points = polyline.points()
            let n = polyline.pointCount
            var best = Double.greatestFiniteMagnitude
            if n < 2 { return best }
            for i in 0..<(n - 1) {
                let a = points[i]
                let b = points[i + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let len2 = dx * dx + dy * dy
                var t = 0.0
                if len2 > 0 {
                    t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
                }
                let d = hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
                if d < best { best = d }
            }
            return best
        }

        /// Tocar una ruta alternativa la elige.
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let map = map, parent.engine.phase == .preview else { return }
            let point = recognizer.location(in: map)
            let mapPoint = MKMapPoint(map.convert(point, toCoordinateFrom: map))
            let tolerance = 26.0 * map.visibleMapRect.size.width / Double(max(1, map.bounds.width))
            var best = -1
            var bestDistance = tolerance
            for (i, route) in parent.engine.routes.enumerated() {
                let d = Coordinator.distance(from: mapPoint, to: route.polyline)
                if d < bestDistance {
                    bestDistance = d
                    best = i
                }
            }
            if best >= 0 {
                parent.engine.select(best)
            }
        }

        /// Mantener pulsado un punto del mapa lo fija como destino.
        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let map = map else { return }
            let phase = parent.engine.phase
            guard phase == .idle || phase == .preview else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            parent.engine.plan(toCoordinate: coordinate, name: "Punto en el mapa")
        }
    }
}
