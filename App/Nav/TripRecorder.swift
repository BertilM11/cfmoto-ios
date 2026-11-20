// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreLocation
import Combine
import UIKit

/// 0.8.0: graba los viajes solo (mientras hay enlace con la moto o navegación) y los guarda.
final class TripRecorder: ObservableObject {
    static let shared = TripRecorder()

    @Published private(set) var trips: [Trip] = []
    @Published private(set) var recording = false

    private var tracker = TripTracker()
    private let store = TripStore()
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        if Demo.mode == "viajes" && store.all().isEmpty { seedDemo() }
        trips = store.all()
        subscription = LocationService.shared.$last
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.feed($0) }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let done = self.tracker.tick(at: Date()) { self.keep(done) }
            self.recording = self.tracker.current != nil
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, let done = self.tracker.flush() else { return }
            self.keep(done)
        }
    }

    private var active: Bool {
        let engine = NavEngine.shared
        return (engine.linkActive || engine.phase == .navigating) && !engine.simulating
    }

    private func feed(_ location: CLLocation) {
        let engine = NavEngine.shared
        let fix = TripTracker.Fix(lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                                  time: location.timestamp, speed: location.speed,
                                  accuracy: location.horizontalAccuracy)
        let wasRecording = tracker.current != nil
        let destination = engine.phase == .navigating ? engine.destinationName : nil
        if let done = tracker.feed(fix, active: active, destination: destination) { keep(done) }
        let now = tracker.current != nil
        if now != wasRecording {
            logLine(now ? "[VIAJE] grabando un viaje nuevo" : "[VIAJE] viaje cerrado")
        }
        if recording != now { recording = now }
    }

    private func keep(_ trip: Trip) {
        store.save(trip)
        trips = store.all()
        logLine(String(format: "[VIAJE] guardado: %.1f km, %d min en movimiento, %d puntos",
                       trip.distance / 1000, Int(trip.movingTime / 60), trip.points.count))
    }

    /// Solo para la prueba automática de capturas: un viaje de ejemplo por la ciudad.
    private func seedDemo() {
        let start = Date().addingTimeInterval(-3 * 3600)
        var trip = Trip(start: start, end: start.addingTimeInterval(1500))
        trip.destination = "Antigua Guatemala"
        let path: [(Double, Double)] = [(14.6349, -90.5069), (14.6150, -90.5300), (14.5980, -90.5650),
                                        (14.5850, -90.6100), (14.5720, -90.6600), (14.5610, -90.7050),
                                        (14.5573, -90.7333)]
        var t = 0.0
        for i in 0..<(path.count - 1) {
            for k in 0..<20 {
                let f = Double(k) / 20
                let lat = path[i].0 + (path[i + 1].0 - path[i].0) * f
                let lon = path[i].1 + (path[i + 1].1 - path[i].1) * f
                trip.points.append(Trip.Point(lat: lat, lon: lon, t: t, v: 12))
                t += 12
            }
        }
        trip.distance = 26_400
        trip.movingTime = 1380
        trip.maxSpeed = 22
        store.save(trip)
    }

    func delete(_ trip: Trip) {
        store.delete(trip)
        trips = store.all()
    }

    /// Escribe el GPX en un archivo temporal para compartirlo.
    func gpxFile(_ trip: Trip) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MotoLink_\(f.string(from: trip.start)).gpx")
        try? trip.gpx().data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
