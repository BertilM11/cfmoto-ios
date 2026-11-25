// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// 0.8.1: avisos de lluvia en la ruta con el pronóstico de Open-Meteo (gratis, sin cuenta;
/// datos con licencia CC BY 4.0, por eso el aviso dice de dónde salen). Se consulta al empezar
/// la guía y cada 15 minutos, en 4 puntos de la ruta y a la hora en que se pasará por cada uno.
/// Sin internet no pasa nada: simplemente no hay aviso.
enum RainForecast {
    struct Sample: Equatable {
        let lat: Double
        let lon: Double
        /// Cuándo se pasará por ese punto.
        let when: Date
    }

    struct Hourly: Equatable {
        /// Inicio de cada hora (segundos desde 1970).
        var times: [Double] = []
        var probability: [Double] = []
        /// Milímetros en esa hora.
        var precipitation: [Double] = []
    }

    struct Alert: Equatable {
        let when: Date
        let probability: Int
        let millimeters: Double
        /// 0 = al salir, 1 = a la llegada.
        let fraction: Double
    }

    static func request(_ samples: [Sample]) -> URLRequest? {
        guard !samples.isEmpty, var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return nil }
        // Privacidad: dos decimales (~1 km) bastan para el pronóstico y no revelan la ubicación exacta.
        c.queryItems = [
            URLQueryItem(name: "latitude", value: samples.map { String(format: "%.2f", $0.lat) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: samples.map { String(format: "%.2f", $0.lon) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "precipitation_probability,precipitation"),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "America/Guatemala"),
        ]
        guard let url = c.url else { return nil }
        return URLRequest(url: url, timeoutInterval: 10)
    }

    /// Una ubicación devuelve un objeto; varias, una lista.
    static func parse(_ data: Data) -> [Hourly] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]] = (json as? [[String: Any]]) ?? ((json as? [String: Any]).map { [$0] } ?? [])
        return list.map { item in
            let h = item["hourly"] as? [String: Any] ?? [:]
            func nums(_ k: String) -> [Double] {
                (h[k] as? [Any] ?? []).map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) }
            }
            return Hourly(times: nums("time"), probability: nums("precipitation_probability"), precipitation: nums("precipitation"))
        }
    }

    /// La primera vez que se pasará por un punto con lluvia probable (≥ 50 %) o llovida
    /// (≥ 0,5 mm en la hora).
    static func firstRain(_ samples: [Sample], _ forecasts: [Hourly]) -> Alert? {
        for (i, s) in samples.enumerated() where i < forecasts.count {
            let f = forecasts[i]
            let t = s.when.timeIntervalSince1970
            guard let h = f.times.lastIndex(where: { $0 <= t }), t - f.times[h] < 3600 else { continue }
            let p = h < f.probability.count ? f.probability[h] : 0
            let mm = h < f.precipitation.count ? f.precipitation[h] : 0
            if p >= 50 || mm >= 0.5 {
                let fraction = samples.count > 1 ? Double(i) / Double(samples.count - 1) : 0
                return Alert(when: s.when, probability: Int(p.rounded()), millimeters: mm, fraction: fraction)
            }
        }
        return nil
    }

    static func text(_ a: Alert) -> String {
        let clock = HUDFormat.clock(a.when)
        let place = a.fraction == 0 ? "al salir" : (a.fraction >= 1 ? "al llegar" : "en el camino")
        return "Posible lluvia \(place), hacia las \(clock.time) \(clock.suffix) (\(a.probability) %)"
    }
}
