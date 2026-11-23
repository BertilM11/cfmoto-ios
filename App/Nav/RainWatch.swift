// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Consulta el pronóstico mientras se navega.
final class RainWatch {
    static let shared = RainWatch()
    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var told = false

    /// Al empezar una guía nueva (no en los recálculos).
    func routeStarted() {
        told = false
        NavEngine.shared.rainNote = nil
        timer?.invalidate()
        guard DashStore.shared.config.map.rainAlerts else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    func routeEnded() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        NavEngine.shared.rainNote = nil
    }

    private func check() {
        let engine = NavEngine.shared
        guard engine.phase == .navigating, !engine.simulating, let samples = engine.rainSamples(),
              let request = RainForecast.request(samples) else { return }
        task?.cancel()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let forecasts = ok ? data.map(RainForecast.parse) ?? [] : []
            DispatchQueue.main.async {
                guard let self = self, NavEngine.shared.phase == .navigating else { return }
                guard !forecasts.isEmpty else {
                    logLine("[LLUVIA] sin pronóstico (sin internet o sin respuesta)")
                    return
                }
                if let alert = RainForecast.firstRain(samples, forecasts) {
                    let text = RainForecast.text(alert)
                    NavEngine.shared.rainNote = text
                    logLine("[LLUVIA] \(text) · Open-Meteo")
                    if !self.told {
                        self.told = true
                        DashStore.shared.notify(.nav, "Posible lluvia en la ruta", text.replacingOccurrences(of: "Posible lluvia ", with: ""))
                        NavEngine.shared.say("Posible lluvia en tu ruta")
                    }
                } else {
                    NavEngine.shared.rainNote = nil
                    logLine("[LLUVIA] sin lluvia probable en la ruta · Open-Meteo")
                }
            }
        }
        task?.resume()
    }
}
