// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// 0.7.4: corrige la hora de llegada por el tráfico.
///
/// Las rutas de OpenStreetMap salen con velocidades de calle libre (en la moto, 27 min
/// calculados fueron 56 a la hora pico). Se corrige de dos formas:
/// 1. Al empezar, según la hora y el día (horas pico de la ciudad de Guatemala).
/// 2. Ya en camino, con el ritmo real: cuánto se tardó en lo recorrido frente a lo calculado.
///    Cuanto más se ha recorrido, más pesa el ritmo real.
/// Las rutas de Apple ya traen el tráfico: empiezan sin corrección y solo usan el ritmo real.
/// Solo cambia el tiempo y la hora de llegada: no cambia la ruta ni las indicaciones.
struct TrafficPace {
    /// Factor actual (1 = como lo calculó la ruta).
    private(set) var factor: Double = 1
    private var startTime: Date?
    private var startProgress: Double = 0
    private var prior: Double = 1
    private var lastUpdate: Date?

    static let minFactor = 0.8
    static let maxFactor = 3.0

    /// Corrección inicial por hora para Guatemala (de lunes a viernes, más en las horas pico;
    /// fines de semana, poca; de noche, nada).
    static func hourFactor(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian),
                           timeZone: TimeZone = TimeZone(identifier: "America/Guatemala") ?? .current) -> Double {
        var cal = calendar
        cal.timeZone = timeZone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let weekend = c.weekday == 1 || c.weekday == 7
        func between(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> Bool {
            minutes >= h1 * 60 + m1 && minutes < h2 * 60 + m2
        }
        if weekend {
            return between(10, 0, 20, 0) ? 1.15 : 1.0
        }
        if between(6, 0, 9, 0) { return 1.6 }
        if between(16, 30, 19, 30) { return 1.7 }
        if between(9, 0, 16, 30) { return 1.25 }
        if between(19, 30, 21, 0) { return 1.15 }
        return 1.0
    }

    // MARK: - 0.9.4: tráfico aprendido de tus viajes
    //
    // Al llegar, se guarda cuánto tardaste de verdad frente a lo calculado, por franja horaria
    // (entre semana / fin de semana y hora de salida). La próxima ruta a esa hora empieza con ese
    // ritmo en lugar del fijo. Solo se guardan números (sin lugares ni rutas), en este iPhone.

    static let learnedKey = "trafficLearned.v1"

    /// Franja de una fecha: «wd-17» (entre semana, 17 h) o «we-10» (fin de semana, 10 h).
    static func slot(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "America/Guatemala") ?? .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.weekday, .hour], from: date)
        let weekend = c.weekday == 1 || c.weekday == 7
        return String(format: "%@-%02d", weekend ? "we" : "wd", c.hour ?? 0)
    }

    /// Factor con el que empieza una ruta: el aprendido de esa franja (si lo hay) o el fijo.
    static func startFactor(_ date: Date, store: [String: Double]) -> Double {
        let fixed = hourFactor(date)
        guard let learned = store[slot(date)] else { return fixed }
        return min(maxFactor, max(minFactor, learned))
    }

    /// Guarda lo observado en un viaje terminado. Se mezcla con lo anterior (60 % / 40 %) para
    /// que un día raro o una parada no lo desajuste. Viajes muy cortos o absurdos no cuentan.
    static func learn(_ store: inout [String: Double], departure: Date, realSeconds: Double, plannedSeconds: Double) -> Double? {
        guard plannedSeconds >= 300, realSeconds > 0 else { return nil }
        let observed = realSeconds / plannedSeconds
        guard observed >= 0.6, observed <= 4 else { return nil }
        let clamped = min(maxFactor, max(minFactor, observed))
        let key = slot(departure)
        let old = store[key] ?? hourFactor(departure)
        let new = old * 0.6 + clamped * 0.4
        store[key] = new
        return new
    }

    static func loadLearned() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: learnedKey) as? [String: Double] ?? [:]
    }

    static func saveLearned(_ store: [String: Double]) {
        UserDefaults.standard.set(store, forKey: learnedKey)
    }

    /// Nueva ruta. `trafficIncluded` = la ruta ya trae el tráfico (Apple). Tras un recálculo
    /// se conserva lo aprendido en el camino.
    mutating func start(at date: Date, progress: Double, trafficIncluded: Bool, keepLearned: Bool) {
        if !keepLearned {
            prior = trafficIncluded ? 1 : Self.startFactor(date, store: Self.loadLearned())
        } else if trafficIncluded {
            prior = max(1, factor * 0.8)
        } else {
            prior = factor
        }
        factor = prior
        startTime = date
        startProgress = progress
        lastUpdate = nil
    }

    /// Actualiza con el avance sobre la ruta. `plannedSeconds` y `length` son los de la ruta
    /// completa. Devuelve el factor a aplicar al tiempo que falta.
    @discardableResult
    mutating func update(at date: Date, progress: Double, length: Double, plannedSeconds: Double) -> Double {
        guard let t0 = startTime, length > 1, plannedSeconds > 1 else { return factor }
        let traveled = max(0, progress - startProgress)
        let elapsed = date.timeIntervalSince(t0)
        var target = prior
        if traveled >= 500 && elapsed >= 120 {
            let plannedTraveled = plannedSeconds * traveled / length
            let observed = min(Self.maxFactor, max(Self.minFactor, elapsed / max(1, plannedTraveled)))
            let weight = min(1, traveled / 4000)
            target = prior * (1 - weight) + observed * weight
        }
        // Se suaviza (unos 20 s) para que la hora de llegada no salte en cada semáforo.
        let dt = lastUpdate.map { min(10, max(0, date.timeIntervalSince($0))) } ?? 10
        let alpha = min(1, dt / 20)
        factor = factor + (target - factor) * alpha
        factor = min(Self.maxFactor, max(Self.minFactor, factor))
        lastUpdate = date
        return factor
    }
}
