// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.8.2: datos de la guía en la pantalla bloqueada (Live Activity). Este archivo lo comparten
// la app y la extensión que la dibuja. Solo texto y números: nada del protocolo de la moto.
import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct NavActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// `ManeuverKind.rawValue`.
        var kind: Int
        /// Metros hasta la próxima maniobra.
        var distance: Double
        var instruction: String
        var remainingDistance: Double
        var eta: Date
        var arrived: Bool
        var rerouting: Bool
        /// km/h de la calle actual (0 = desconocida).
        var speedLimit: Int
    }

    var destination: String
}
#endif

/// Formato común de la guía en la pantalla bloqueada.
enum LiveFormat {
    /// Símbolo de SF Symbols para cada maniobra (mismo orden que `ManeuverKind`).
    static func symbol(kind: Int, arrived: Bool) -> String {
        if arrived { return "flag.checkered" }
        switch kind {
        case 0, 1: return "arrow.up"
        case 2, 10: return "arrow.up.left"
        case 3, 4: return "arrow.turn.up.left"
        case 5, 11: return "arrow.up.right"
        case 6, 7: return "arrow.turn.up.right"
        case 8: return "arrow.uturn.left"
        case 9: return "arrow.triangle.turn.up.right.circle"
        case 12: return "flag.checkered"
        default: return "arrow.up"
        }
    }

    static func distance(_ meters: Double) -> String {
        let m = max(0, meters)
        if m < 1000 {
            let step: Double = m < 100 ? 10 : 50
            return "\(Int((m / step).rounded() * step)) m"
        }
        if m < 10_000 { return String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ",") }
        return "\(Int((m / 1000).rounded())) km"
    }
}
