// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import MapKit
import CoreLocation
import CoreGraphics

/// Una maniobra de la ruta: dónde ocurre, de qué tipo es y su texto (de Apple Maps o propio).
struct RouteManeuver {
    /// Metros desde el inicio de la ruta.
    let at: Double
    let kind: ManeuverKind
    let text: String
}

struct RouteSnap {
    let segment: Int
    /// Metros recorridos sobre la ruta.
    let along: Double
    /// Distancia lateral a la ruta, en metros.
    let lateral: Double
}

/// Una ruta (de Apple Maps o del mapa propio de OpenStreetMap) preparada para guiar: geometría
/// en metros, maniobras ordenadas y proyección de la posición GPS sobre la línea.
final class GuidedRoute {
    let route: PlannedRoute
    let shape: HUDRouteShape
    let maneuvers: [RouteManeuver]
    /// Cómo se emparejaron los textos con los cruces (para el registro de diagnóstico).
    let convention: String

    private let origin: CLLocationCoordinate2D
    private let metersPerLat: Double
    private let metersPerLon: Double

    /// Lo mismo que `local`/`coordinate`, en el formato que usa el dibujo de la moto.
    var geoFrame: GeoFrame { GeoFrame(origin: GeoPoint(lat: origin.latitude, lon: origin.longitude)) }

    init(route: PlannedRoute) {
        self.route = route
        let coordinates = route.coordinates
        let o = coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let mLat = 110_574.0
        let mLon = 111_320.0 * cos(o.latitude * .pi / 180)
        origin = o
        metersPerLat = mLat
        metersPerLon = mLon
        let s = HUDRouteShape(points: coordinates.map {
            CGPoint(x: ($0.longitude - o.longitude) * mLon, y: ($0.latitude - o.latitude) * mLat)
        })
        shape = s
        if let apple = route.apple {
            let built = GuidedRoute.buildManeuvers(route: apple, shape: s, mLat: mLat, mLon: mLon)
            maneuvers = built.list
            convention = built.convention
        } else {
            maneuvers = GuidedRoute.placeOSM(route, shape: s)
            convention = "maniobras propias de OpenStreetMap"
        }
    }

    // MARK: - Conversión de coordenadas

    func local(_ c: CLLocationCoordinate2D) -> CGPoint {
        CGPoint(x: (c.longitude - origin.longitude) * metersPerLon, y: (c.latitude - origin.latitude) * metersPerLat)
    }

    func coordinate(_ p: CGPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: origin.latitude + Double(p.y) / metersPerLat,
            longitude: origin.longitude + Double(p.x) / metersPerLon
        )
    }

    static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let n = polyline.pointCount
        guard n > 0 else { return [] }
        var c = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0), count: n)
        polyline.getCoordinates(&c, range: NSRange(location: 0, length: n))
        return c
    }

    // MARK: - Posición sobre la ruta

    /// Proyecta un punto sobre la ruta. Busca primero cerca de la posición anterior para no
    /// saltar a otro tramo que pase al lado (pasos a desnivel, calles paralelas).
    func snap(_ p: CGPoint, hint: Int, lastProgress: Double) -> RouteSnap {
        let pts = shape.points
        let cum = shape.cumulative
        let n = pts.count
        guard n >= 2 else { return RouteSnap(segment: 0, along: 0, lateral: .greatestFiniteMagnitude) }

        func best(_ lower: Int, _ upper: Int) -> RouteSnap {
            var bestDistance = Double.greatestFiniteMagnitude
            var bestSegment = lower
            var bestT = 0.0
            var i = lower
            while i <= upper {
                let a = pts[i]
                let b = pts[i + 1]
                let dx = Double(b.x - a.x)
                let dy = Double(b.y - a.y)
                let len2 = dx * dx + dy * dy
                var t = 0.0
                if len2 > 0 {
                    t = (Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / len2
                    t = max(0, min(1, t))
                }
                let qx = Double(a.x) + t * dx
                let qy = Double(a.y) + t * dy
                let d = hypot(Double(p.x) - qx, Double(p.y) - qy)
                if d < bestDistance {
                    bestDistance = d
                    bestSegment = i
                    bestT = t
                }
                i += 1
            }
            let along = cum[bestSegment] + bestT * (cum[bestSegment + 1] - cum[bestSegment])
            return RouteSnap(segment: bestSegment, along: along, lateral: bestDistance)
        }

        let start = max(0, min(hint, n - 2))
        let lower = max(0, start - 4)
        var upper = min(n - 2, start + 8)
        while upper < n - 2 && cum[upper] < lastProgress + 350 {
            upper += 1
        }
        let near = best(lower, upper)
        if near.lateral <= 35 { return near }
        let anywhere = best(0, n - 2)
        return anywhere.lateral + 15 < near.lateral ? anywhere : near
    }

    // MARK: - Maniobras

    /// Ángulo del giro en un punto de la ruta, en grados. Positivo = derecha.
    static func turnAngle(_ shape: HUDRouteShape, at d: Double) -> Double {
        let length = shape.length
        if d < 6 || d > length - 6 { return 0 }
        let a0 = shape.point(at: max(0, d - 30))
        let a1 = shape.point(at: max(0, d - 5))
        let b0 = shape.point(at: min(length, d + 5))
        let b1 = shape.point(at: min(length, d + 30))
        let incoming = atan2(Double(a1.x - a0.x), Double(a1.y - a0.y))
        let outgoing = atan2(Double(b1.x - b0.x), Double(b1.y - b0.y))
        var delta = (outgoing - incoming) * 180 / .pi
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }

    private static func firstMatch(_ folded: String, _ pattern: String) -> String.Index? {
        folded.range(of: pattern, options: .regularExpression)?.lowerBound
    }

    /// Lado que nombra el texto: -1 izquierda, +1 derecha, 0 ninguno.
    private static func side(_ folded: String) -> Int {
        let left = firstMatch(folded, "\\b(izquierda|left)\\b")
        let right = firstMatch(folded, "\\b(derecha|right)\\b")
        switch (left, right) {
        case (nil, nil): return 0
        case (.some, nil): return -1
        case (nil, .some): return 1
        case (.some(let l), .some(let r)): return l < r ? -1 : 1
        }
    }

    private static func has(_ folded: String, _ words: [String]) -> Bool {
        words.contains { folded.contains($0) }
    }

    private static func fromAngle(_ angle: Double) -> ManeuverKind {
        let a = abs(angle)
        let right = angle > 0
        if a < 25 { return .straight }
        if a < 55 { return right ? .slightRight : .slightLeft }
        if a < 125 { return right ? .right : .left }
        if a < 165 { return right ? .sharpRight : .sharpLeft }
        return right ? .sharpRight : .uTurn
    }

    private static func classify(_ text: String, angle: Double) -> ManeuverKind {
        let t = fold(text)
        if has(t, ["rotonda", "redondel", "glorieta", "roundabout", "traffic circle", "rotary"]) {
            return .roundabout
        }
        if has(t, ["vuelta en u", "cambio de sentido", "media vuelta", "retorno", "u-turn", "u turn"]) {
            return .uTurn
        }
        let s = side(t)
        if has(t, ["mantente", "mantengase", "permanece", "keep "]) {
            if s < 0 { return .keepLeft }
            if s > 0 { return .keepRight }
            return .straight
        }
        if s == 0 {
            // El texto no dice lado: fiarse de la forma de la ruta.
            return fromAngle(angle)
        }
        let a = abs(angle)
        if has(t, ["ligeramente", "leve", "slight"]) {
            return s > 0 ? .slightRight : .slightLeft
        }
        if has(t, ["cerrad", "pronunciad", "sharp"]) {
            return s > 0 ? .sharpRight : .sharpLeft
        }
        if has(t, ["salida", "exit", "rampa", "ramp"]) && a < 55 {
            return s > 0 ? .slightRight : .slightLeft
        }
        if a < 25 {
            // La geometría no muestra el giro con claridad: creer al texto.
            return s > 0 ? .right : .left
        }
        return fromAngle(s > 0 ? a : -a)
    }

    private static func defaultText(_ kind: ManeuverKind) -> String {
        switch kind {
        case .depart: return "Inicia el recorrido"
        case .straight: return "Continúa recto"
        case .slightLeft: return "Gira ligeramente a la izquierda"
        case .left: return "Gira a la izquierda"
        case .sharpLeft: return "Gira cerrado a la izquierda"
        case .slightRight: return "Gira ligeramente a la derecha"
        case .right: return "Gira a la derecha"
        case .sharpRight: return "Gira cerrado a la derecha"
        case .uTurn: return "Da la vuelta"
        case .roundabout: return "Entra en la rotonda"
        case .keepLeft: return "Mantente a la izquierda"
        case .keepRight: return "Mantente a la derecha"
        case .arrive: return "Has llegado a tu destino"
        }
    }

    private static func length(of polyline: MKPolyline, mLat: Double, mLon: Double) -> Double {
        let c = coordinates(of: polyline)
        if c.count < 2 { return 0 }
        var total = 0.0
        for i in 1..<c.count {
            total += hypot((c[i].longitude - c[i - 1].longitude) * mLon, (c[i].latitude - c[i - 1].latitude) * mLat)
        }
        return total
    }

    /// Sitúa las maniobras del router de OpenStreetMap sobre la forma de la ruta. El router mide
    /// cada tramo con su propia latitud y la forma usa una sola referencia para toda la ruta; se
    /// pasa de una medida a la otra tramo a tramo, así cada giro cae justo en su cruce aunque la
    /// ruta sea larga.
    static func placeOSM(_ route: PlannedRoute, shape: HUDRouteShape) -> [RouteManeuver] {
        let c = route.coordinates
        let cum = shape.cumulative
        guard c.count >= 2, cum.count == c.count else {
            return [RouteManeuver(at: shape.length, kind: .arrive, text: defaultText(.arrive))]
        }
        var measured: [Double] = [0]
        measured.reserveCapacity(c.count)
        for i in 1..<c.count {
            let a = GeoPoint(lat: c[i - 1].latitude, lon: c[i - 1].longitude)
            let b = GeoPoint(lat: c[i].latitude, lon: c[i].longitude)
            measured.append(measured[i - 1] + a.distance(to: b))
        }
        let total = measured[measured.count - 1]
        func place(_ d: Double) -> Double {
            guard total > 0 else { return 0 }
            let x = max(0, min(total, d))
            var lo = 0
            var hi = measured.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if measured[mid] <= x { lo = mid } else { hi = mid }
            }
            let seg = measured[hi] - measured[lo]
            let f = seg > 0 ? (x - measured[lo]) / seg : 0
            return cum[lo] + f * (cum[hi] - cum[lo])
        }
        var list: [RouteManeuver] = []
        for m in route.osmManeuvers {
            let at = m.kind == .arrive ? shape.length : min(shape.length, place(m.at))
            if at < 3 && m.kind != .arrive { continue }   // la salida no es una maniobra
            if let previous = list.last, abs(previous.at - at) < 2 { continue }
            list.append(RouteManeuver(at: at, kind: m.kind, text: m.text.isEmpty ? defaultText(m.kind) : m.text))
        }
        if list.last?.kind != .arrive {
            list.append(RouteManeuver(at: shape.length, kind: .arrive, text: defaultText(.arrive)))
        }
        return list
    }

    /// Convierte los pasos de Apple Maps en maniobras situadas sobre la ruta.
    ///
    /// Cada paso trae un texto y un tramo de la línea, pero la documentación no aclara si el
    /// texto describe el giro del principio del tramo o el del final. Se prueban las dos
    /// lecturas y se elige la que mejor concuerda con la forma real de la ruta (un texto que
    /// dice "derecha" debe caer en un cruce que gira a la derecha).
    private static func buildManeuvers(
        route: MKRoute, shape: HUDRouteShape, mLat: Double, mLon: Double
    ) -> (list: [RouteManeuver], convention: String) {
        let steps = route.steps
        let total = shape.length
        guard !steps.isEmpty, total > 1 else {
            return ([RouteManeuver(at: total, kind: .arrive, text: defaultText(.arrive))], "sin pasos")
        }

        var lengths = steps.map { length(of: $0.polyline, mLat: mLat, mLon: mLon) }
        var sum = lengths.reduce(0, +)
        if sum < 1 {
            lengths = steps.map { $0.distance }
            sum = lengths.reduce(0, +)
        }
        let scale = sum > 1 ? total / sum : 1
        var bounds: [Double] = [0]
        for l in lengths {
            bounds.append(min(total, (bounds.last ?? 0) + l * scale))
        }

        // Lectura A: el texto es el giro al empezar el tramo. Lectura B: al terminarlo.
        var readingA: [(at: Double, text: String)] = []
        var readingB: [(at: Double, text: String)] = []
        for i in 0..<steps.count {
            let text = steps[i].instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if i > 0 { readingA.append((bounds[i], text)) }
            readingB.append((bounds[i + 1], text))
        }

        func score(_ events: [(at: Double, text: String)]) -> Int {
            var points = 0
            for event in events where event.at > 8 && event.at < total - 8 {
                let angle = turnAngle(shape, at: event.at)
                let s = side(fold(event.text))
                if s == 0 || abs(angle) < 35 { continue }
                points += (s > 0) == (angle > 0) ? 1 : -1
            }
            return points
        }

        let scoreA = score(readingA)
        let scoreB = score(readingB)
        let lastLength = (lengths.last ?? 0) * scale
        let useB: Bool
        if scoreA != scoreB {
            useB = scoreB > scoreA
        } else {
            // Empate: si el último tramo tiene longitud, su texto (la llegada) va al final.
            useB = lastLength > 2.5
        }
        let events = useB ? readingB : readingA
        let convention = "\(useB ? "final" : "inicio") del tramo (A=\(scoreA), B=\(scoreB))"

        var list: [RouteManeuver] = []
        for event in events {
            if event.at < 3 { continue }   // la salida no es una maniobra
            let atEnd = event.at > total - 3
            let kind: ManeuverKind = atEnd ? .arrive : classify(event.text, angle: turnAngle(shape, at: event.at))
            if kind == .straight && event.text.isEmpty { continue }
            if let previous = list.last, abs(previous.at - event.at) < 2 { continue }
            let text = event.text.isEmpty ? defaultText(kind) : event.text
            list.append(RouteManeuver(at: min(event.at, total), kind: kind, text: text))
        }
        if list.last?.kind != .arrive {
            list.append(RouteManeuver(at: total, kind: .arrive, text: defaultText(.arrive)))
        }
        return (list, convention)
    }
}
