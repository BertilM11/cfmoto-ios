// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import MapKit
import CoreLocation

/// Una ruta propuesta, calculada por Apple Maps o por el mapa propio de OpenStreetMap que viene
/// en la app. La interfaz del iPhone, la guía y la pantalla de la moto la usan igual venga de
/// donde venga.
final class PlannedRoute {
    enum Source {
        case apple
        case osm
    }

    let source: Source
    let coordinates: [CLLocationCoordinate2D]
    /// Metros.
    let distance: Double
    /// Segundos previstos.
    let expectedTravelTime: TimeInterval

    /// 0.7.4: tiempo previsto con el tráfico según la hora (las rutas de Apple ya lo traen).
    var estimatedTime: TimeInterval {
        source == .apple ? expectedTravelTime : expectedTravelTime * TrafficPace.hourFactor(Date())
    }
    /// Calles principales de la ruta («Avenida La Reforma y 14 Calle»).
    let name: String
    /// La ruta original de Apple (solo en el modo Apple Maps).
    let apple: MKRoute?
    /// Maniobras de la ruta de OpenStreetMap, en metros desde el inicio según el router.
    let osmManeuvers: [(at: Double, kind: ManeuverKind, text: String)]
    /// Pasos con su texto, para el registro de diagnóstico.
    let steps: [(distance: Double, text: String)]
    /// La línea para el mapa del iPhone.
    let polyline: MKPolyline

    init(apple route: MKRoute) {
        source = .apple
        apple = route
        coordinates = GuidedRoute.coordinates(of: route.polyline)
        distance = route.distance
        expectedTravelTime = route.expectedTravelTime
        name = route.name
        osmManeuvers = []
        steps = route.steps.map { (distance: $0.distance, text: $0.instructions) }
        polyline = route.polyline
    }

    init(osm route: OSMRoute) {
        source = .osm
        apple = nil
        let c = route.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        coordinates = c
        distance = route.distance
        expectedTravelTime = route.time
        // El resumen del router ya empieza con «por»; la interfaz lo añade ella misma.
        name = route.summary.hasPrefix("por ") ? String(route.summary.dropFirst(4)) : route.summary
        osmManeuvers = route.maneuvers
        var list: [(distance: Double, text: String)] = []
        var previous = 0.0
        for m in route.maneuvers {
            list.append((distance: m.at - previous, text: m.text))
            previous = m.at
        }
        steps = list
        var line = c
        polyline = MKPolyline(coordinates: &line, count: line.count)
    }
}
