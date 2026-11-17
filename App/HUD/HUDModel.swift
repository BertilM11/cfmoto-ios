// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreGraphics

/// Tipo de maniobra. Lo comparten la guía, la interfaz del iPhone y el dibujo para la moto.
enum ManeuverKind: Int {
    case depart
    case straight
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case uTurn
    case roundabout
    case keepLeft
    case keepRight
    case arrive
}

enum HUDStyle {
    case day
    case night
}

/// Geometría de la ruta en metros locales (x = este, y = norte). Es inmutable, así que se
/// puede leer desde cualquier hilo.
final class HUDRouteShape {
    let points: [CGPoint]
    let cumulative: [Double]
    let length: Double

    init(points: [CGPoint]) {
        self.points = points
        var cum: [Double] = []
        cum.reserveCapacity(points.count)
        var total = 0.0
        for i in 0..<points.count {
            if i > 0 {
                total += Double(hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            cum.append(total)
        }
        cumulative = cum
        length = total
    }

    /// Índice del segmento que contiene la distancia dada (búsqueda binaria).
    func segmentIndex(at distance: Double) -> Int {
        let n = points.count
        if n < 2 { return 0 }
        if distance <= 0 { return 0 }
        if distance >= length { return n - 2 }
        var lo = 0
        var hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= distance {
                lo = mid
            } else {
                hi = mid
            }
        }
        return min(lo, n - 2)
    }

    func point(at distance: Double) -> CGPoint {
        let n = points.count
        if n == 0 { return .zero }
        if n == 1 { return points[0] }
        let d = max(0, min(length, distance))
        let i = segmentIndex(at: d)
        let segment = cumulative[i + 1] - cumulative[i]
        let t = segment > 0 ? (d - cumulative[i]) / segment : 0
        let a = points[i]
        let b = points[i + 1]
        return CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }

    /// Rumbo en radianes (0 = norte, sentido horario) mirando `span` metros hacia delante.
    func bearing(at distance: Double, span: Double = 12) -> Double {
        let a = point(at: distance)
        let b = point(at: distance + span)
        if hypot(b.x - a.x, b.y - a.y) < 0.5 {
            // Final de la ruta: mirar hacia atrás.
            let c = point(at: distance - span)
            return Double(atan2(a.x - c.x, a.y - c.y))
        }
        return Double(atan2(b.x - a.x, b.y - a.y))
    }
}

/// Todo lo necesario para dibujar un fotograma en la moto. Es un valor: se copia entre hilos.
struct HUDSnapshot {
    var navigating = false
    var arrived = false
    var rerouting = false
    var simulated = false
    var gpsOk = false
    var kind: ManeuverKind = .straight
    var distanceToManeuver: Double = 0
    var instruction: String = ""
    var thenKind: ManeuverKind?
    var remainingDistance: Double = 0
    var remainingTime: TimeInterval = 0
    var eta: Date?
    var fraction: Double = 0
    var shape: HUDRouteShape?
    /// Metros recorridos sobre la ruta en el último fijo.
    var progress: Double = 0
    /// Posición de la próxima maniobra sobre la ruta, en metros.
    var maneuverAt: Double?
    /// Velocidad en m/s, para avanzar la posición entre fijos del GPS.
    var speed: Double = 0
    /// Momento del último fijo (segundos desde la fecha de referencia).
    var fixTime: TimeInterval = 0
    var style: HUDStyle = .night
    var destinationName: String = ""
    /// Para pasar los metros de la ruta a coordenadas (y situarlos en el mapa de calles).
    var geo: GeoFrame?
    /// Última posición del GPS, también sin ruta (para mostrar el mapa alrededor).
    var here: GeoPoint?
    /// Rumbo del GPS en grados (negativo si no se conoce).
    var course: Double = -1
    /// Rutas alternativas, en los mismos metros locales que la ruta.
    var alternates: [[CGPoint]] = []
    /// Rutas propuestas antes de empezar (la elegida y las demás), en coordenadas.
    var previewRoutes: [[GeoPoint]] = []
    var previewSelected = 0
}

/// Textos de distancia, duración y hora. Los usan el iPhone y la moto para decir lo mismo.
enum HUDFormat {
    static func distanceParts(_ meters: Double) -> (value: String, unit: String) {
        let m = max(0, meters)
        if m < 1000 {
            let step: Double = m < 100 ? 10 : 50
            let rounded = (m / step).rounded() * step
            if rounded >= 1000 { return ("1.0", "km") }
            return (String(Int(rounded)), "m")
        }
        if m < 10_000 {
            return (String(format: "%.1f", m / 1000), "km")
        }
        return (String(Int((m / 1000).rounded())), "km")
    }

    static func distance(_ meters: Double) -> String {
        let p = distanceParts(meters)
        return p.value + " " + p.unit
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Versión corta para columnas estrechas: "18 min", "1 h 05".
    static func durationCompact(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    static func clock(_ date: Date) -> (time: String, suffix: String) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        return (String(format: "%d:%02d", h12, m), h < 12 ? "a.m." : "p.m.")
    }
}
