// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// 0.8.0: un viaje grabado (queda solo en este iPhone).
struct Trip: Codable, Identifiable, Equatable {
    struct Point: Codable, Equatable {
        let lat: Double
        let lon: Double
        /// Segundos desde el inicio del viaje.
        let t: Double
        /// Velocidad en m/s (-1 si el GPS no la dio).
        let v: Double
    }

    var id = UUID()
    var start: Date
    var end: Date
    /// Metros recorridos.
    var distance: Double = 0
    /// Segundos en movimiento (sin contar paradas).
    var movingTime: Double = 0
    /// Velocidad máxima en m/s.
    var maxSpeed: Double = 0
    /// Destino de la navegación, si la hubo.
    var destination: String?
    var points: [Point] = []

    var duration: Double { end.timeIntervalSince(start) }

    /// Velocidad promedio en movimiento (m/s).
    var averageSpeed: Double { movingTime > 1 ? distance / movingTime : 0 }

    /// El recorrido en formato GPX (para Google Earth, Strava, etc.).
    func gpx() -> String {
        let iso = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="MotoLink" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(Trip.escape(title))</name><trkseg>

        """
        for p in points {
            let time = iso.string(from: start.addingTimeInterval(p.t))
            out += String(format: "    <trkpt lat=\"%.6f\" lon=\"%.6f\"><time>%@</time></trkpt>\n", p.lat, p.lon, time)
        }
        out += "  </trkseg></trk>\n</gpx>\n"
        return out
    }

    var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_GT")
        f.dateFormat = "d 'de' MMMM, h:mm a"
        let when = f.string(from: start)
        if let d = destination, !d.isEmpty { return "\(when) · a \(d)" }
        return when
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Arma los viajes a partir de los fijos del GPS (sin depender de CoreLocation, para poder
/// probarlo). Un viaje empieza cuando hay enlace con la moto o navegación y la moto se
/// mueve; termina tras 3 minutos sin enlace ni navegación (o 10 minutos detenido).
struct TripTracker {
    struct Fix {
        let lat: Double
        let lon: Double
        let time: Date
        /// m/s (-1 si no hay).
        let speed: Double
        /// metros
        let accuracy: Double
    }

    static let inactiveTimeout: Double = 180
    static let stoppedTimeout: Double = 600
    static let minDistance: Double = 300
    static let movingSpeed: Double = 1.5

    private(set) var current: Trip?
    private var lastFix: Fix?
    private var lastActive: Date?
    private var lastMoving: Date?
    private var lastStored: Fix?

    /// Se llama con cada fijo. Devuelve un viaje terminado cuando corresponde.
    mutating func feed(_ fix: Fix, active: Bool, destination: String?) -> Trip? {
        var finished: Trip?
        if active { lastActive = fix.time }
        if current != nil, let reason = shouldFinish(at: fix.time) {
            finished = finish(reason)
        }
        guard fix.accuracy >= 0, fix.accuracy <= 30 else { return finished }

        let speed = fix.speed >= 0 ? fix.speed : (lastFix.map { estimate(from: $0, to: fix) } ?? 0)
        if current == nil {
            guard active, speed >= Self.movingSpeed else {
                lastFix = fix
                return finished
            }
            current = Trip(start: fix.time, end: fix.time)
            lastStored = nil
            lastMoving = fix.time
            lastFix = nil
        }
        guard var trip = current else { return finished }
        if let d = destination, !d.isEmpty { trip.destination = d }

        if let prev = lastFix {
            let dt = fix.time.timeIntervalSince(prev.time)
            let dist = Self.distance(prev.lat, prev.lon, fix.lat, fix.lon)
            // Saltos imposibles del GPS (más de 70 m/s ≈ 250 km/h) no cuentan.
            if dt > 0 && dist / dt < 70 {
                trip.distance += dist
                if speed >= Self.movingSpeed && dt < 30 { trip.movingTime += dt }
            }
        }
        if speed >= Self.movingSpeed { lastMoving = fix.time }
        trip.maxSpeed = max(trip.maxSpeed, min(speed, 70))
        trip.end = fix.time

        // Se guarda un punto cada 15 m o cada 10 s (suficiente para dibujar el recorrido).
        let store = lastStored.map {
            Self.distance($0.lat, $0.lon, fix.lat, fix.lon) >= 15 || fix.time.timeIntervalSince($0.time) >= 10
        } ?? true
        if store {
            trip.points.append(Trip.Point(lat: fix.lat, lon: fix.lon, t: fix.time.timeIntervalSince(trip.start), v: speed))
            lastStored = fix
        }
        current = trip
        lastFix = fix
        return finished
    }

    /// Revisión periódica (aunque no lleguen fijos, por ejemplo con la moto apagada).
    mutating func tick(at date: Date) -> Trip? {
        guard current != nil, let reason = shouldFinish(at: date) else { return nil }
        return finish(reason)
    }

    /// Cierra el viaje en curso (por ejemplo, al cerrar la app).
    mutating func flush() -> Trip? {
        current == nil ? nil : finish("cerrado")
    }

    private func shouldFinish(at date: Date) -> String? {
        if let a = lastActive, date.timeIntervalSince(a) > Self.inactiveTimeout { return "sin moto ni navegación" }
        if let m = lastMoving, date.timeIntervalSince(m) > Self.stoppedTimeout { return "detenido" }
        return nil
    }

    private mutating func finish(_ reason: String) -> Trip? {
        guard var trip = current else { return nil }
        current = nil
        lastFix = nil
        lastStored = nil
        // El final es el último momento en movimiento (no los minutos esperando).
        if let m = lastMoving, m < trip.end, m > trip.start { trip.end = m }
        return trip.distance >= Self.minDistance ? trip : nil
    }

    private func estimate(from a: Fix, to b: Fix) -> Double {
        let dt = b.time.timeIntervalSince(a.time)
        return dt > 0 ? Self.distance(a.lat, a.lon, b.lat, b.lon) / dt : 0
    }

    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Los viajes guardados, un archivo por viaje en la carpeta de la app.
final class TripStore {
    static let maxTrips = 300
    let folder: URL

    init(folder: URL? = nil) {
        if let f = folder {
            self.folder = f
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.folder = base.appendingPathComponent("Viajes", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    func save(_ trip: Trip) {
        let url = folder.appendingPathComponent(trip.id.uuidString + ".json")
        if let data = try? JSONEncoder().encode(trip) {
            try? data.write(to: url, options: .atomic)
        }
        trim()
    }

    func all() -> [Trip] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Trip.self, from: Data(contentsOf: $0)) }
            .sorted { $0.start > $1.start }
    }

    func delete(_ trip: Trip) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(trip.id.uuidString + ".json"))
    }

    private func trim() {
        let trips = all()
        guard trips.count > Self.maxTrips else { return }
        for t in trips.suffix(from: Self.maxTrips) { delete(t) }
    }
}
