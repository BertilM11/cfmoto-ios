// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mapa de calles de fondo para la moto: una imagen de Apple Maps y la forma de situar en ella
// cualquier punto (ruta, posición, norte). Sin UIKit ni MapKit: lo comparten el dibujo, la
// vista previa y las pruebas en macOS.
import Foundation
import CoreGraphics
import ImageIO

struct GeoPoint: Equatable, Codable {
    var lat: Double
    var lon: Double

    /// Punto a `meters` en la dirección `bearing` (grados desde el norte, sentido horario).
    func moved(_ meters: Double, bearing: Double) -> GeoPoint {
        let b = bearing * .pi / 180
        let north = cos(b) * meters
        let east = sin(b) * meters
        return GeoPoint(
            lat: lat + north / 110_574.0,
            lon: lon + east / (111_320.0 * max(0.01, cos(lat * .pi / 180)))
        )
    }

    /// Distancia aproximada en metros (suficiente para tramos cortos).
    func distance(to o: GeoPoint) -> Double {
        let dy = (o.lat - lat) * 110_574.0
        let dx = (o.lon - lon) * 111_320.0 * cos(lat * .pi / 180)
        return hypot(dx, dy)
    }
}

/// Conversión entre los metros locales de la ruta (x = este, y = norte) y coordenadas. Usa
/// las mismas constantes que la ruta guiada, así que el resultado coincide exactamente.
struct GeoFrame: Equatable {
    var origin: GeoPoint
    var mLat: Double
    var mLon: Double

    init(origin: GeoPoint) {
        self.origin = origin
        mLat = 110_574.0
        mLon = 111_320.0 * cos(origin.lat * .pi / 180)
    }

    func geo(_ p: CGPoint) -> GeoPoint {
        GeoPoint(lat: origin.lat + Double(p.y) / mLat, lon: origin.lon + Double(p.x) / mLon)
    }

    func local(_ g: GeoPoint) -> CGPoint {
        CGPoint(x: (g.lon - origin.lon) * mLon, y: (g.lat - origin.lat) * mLat)
    }
}

/// Proyección de Mercator con la misma escala que usa MapKit (MKMapPoint).
enum Mercator {
    static let world = 268_435_456.0

    static func point(_ g: GeoPoint) -> (x: Double, y: Double) {
        let x = (g.lon + 180) / 360 * world
        let lat = max(-85.05112878, min(85.05112878, g.lat)) * .pi / 180
        let y = (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * world
        return (x, y)
    }

    /// Puntos de mapa por metro a esa latitud.
    static func pointsPerMeter(atLatitude lat: Double) -> Double {
        world / (40_075_016.686 * max(0.01, cos(lat * .pi / 180)))
    }
}

/// Transformación proyectiva de 3×3 (el último coeficiente vale 1). Sirve igual para un mapa
/// plano (2D) que para uno inclinado (3D): un plano visto en perspectiva es una homografía.
struct Homography: Equatable {
    var m: [Double]

    static let identity = Homography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    func apply(_ x: Double, _ y: Double) -> CGPoint? {
        let w = m[6] * x + m[7] * y + m[8]
        guard w > 1e-9 else { return nil }
        let u = (m[0] * x + m[1] * y + m[2]) / w
        let v = (m[3] * x + m[4] * y + m[5]) / w
        guard u.isFinite, v.isFinite else { return nil }
        return CGPoint(x: u, y: v)
    }

    /// La transformación que lleva cuatro puntos de origen a cuatro de destino.
    static func fit(from src: [(Double, Double)], to dst: [(Double, Double)]) -> Homography? {
        guard src.count == 4, dst.count == 4 else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = src[i]
            let (u, v) = dst[i]
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        for col in 0..<8 {
            var pivot = col
            for r in col..<8 where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            for r in 0..<8 where r != col {
                let f = a[r][col] / a[col][col]
                if f != 0 {
                    for c in col..<9 { a[r][c] -= f * a[col][c] }
                }
            }
        }
        var h = [Double](repeating: 0, count: 9)
        for i in 0..<8 { h[i] = a[i][8] / a[i][i] }
        h[8] = 1
        guard h.allSatisfy({ $0.isFinite }) else { return nil }
        return Homography(m: h)
    }
}

/// Una imagen de mapa real y su proyección. Inmutable salvo la imagen decodificada, que se
/// protege con un candado porque la lee el hilo de dibujo.
final class MapBase {
    /// Momento de la captura (segundos desde la fecha de referencia).
    let created: TimeInterval
    let center: GeoPoint
    /// Rumbo de la cámara, en grados desde el norte.
    let heading: Double
    let pitch: Double
    let night: Bool
    /// true: instantánea en vivo; false: guardada a lo largo de la ruta para el iPhone bloqueado.
    let live: Bool
    /// Metros de ruta a los que corresponde (solo las guardadas a lo largo de la ruta).
    let anchor: Double
    /// Tamaño de la imagen en píxeles.
    let pixelWidth: Int
    let pixelHeight: Int
    /// Etiqueta del estilo con el que se pidió, para descartarla si el estilo cambia.
    let styleKey: String

    private let ox: Double
    private let oy: Double
    private let scale: Double
    private let h: Homography
    private let lock = NSLock()
    private var image: CGImage?
    private let data: Data?

    /// `samples`: puntos del terreno y dónde caen en la imagen (0…1 en cada eje).
    init?(
        image: CGImage?, data: Data?, pixelWidth: Int, pixelHeight: Int,
        center: GeoPoint, heading: Double, pitch: Double, night: Bool, live: Bool,
        anchor: Double = -1, created: TimeInterval, styleKey: String,
        samples: [(GeoPoint, CGPoint)]
    ) {
        guard image != nil || data != nil, samples.count == 4, pixelWidth > 0, pixelHeight > 0 else { return nil }
        let c = Mercator.point(center)
        let s = 1 / (Mercator.pointsPerMeter(atLatitude: center.lat) * 100)
        var src: [(Double, Double)] = []
        var dst: [(Double, Double)] = []
        for (g, p) in samples {
            let q = Mercator.point(g)
            src.append(((q.x - c.x) * s, (q.y - c.y) * s))
            dst.append((Double(p.x), Double(p.y)))
        }
        guard let fit = Homography.fit(from: src, to: dst) else { return nil }
        h = fit
        ox = c.x
        oy = c.y
        scale = s
        self.image = image
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.center = center
        self.heading = heading
        self.pitch = pitch
        self.night = night
        self.live = live
        self.anchor = anchor
        self.created = created
        self.styleKey = styleKey
    }

    /// Dónde cae un punto en la imagen (0…1 en cada eje). nil si queda detrás de la cámara.
    func project(_ g: GeoPoint) -> CGPoint? {
        let q = Mercator.point(g)
        return h.apply((q.x - ox) * scale, (q.y - oy) * scale)
    }

    var aspect: CGFloat { CGFloat(pixelWidth) / CGFloat(pixelHeight) }

    /// Cuánto de perspectiva tiene la imagen (0 = mapa plano visto desde arriba).
    var perspective: Double { abs(h.m[6]) + abs(h.m[7]) }

    /// La imagen lista para dibujar. Las guardadas para la ruta se descomprimen al usarlas.
    func cgImage() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let image = image { return image }
        guard let data = data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        image = CGImageSourceCreateImageAtIndex(source, 0, options)
        return image
    }

    /// Libera la imagen descomprimida si se puede volver a obtener de los datos guardados.
    func releaseDecoded() {
        lock.lock()
        if data != nil { image = nil }
        lock.unlock()
    }
}

// MARK: - Ajustes del mapa

enum MapStyle: String, Codable, CaseIterable, Identifiable {
    case standard, muted, hybrid, satellite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Estándar"
        case .muted: return "Atenuado"
        case .hybrid: return "Híbrido"
        case .satellite: return "Satélite"
        }
    }
}

enum MapLabelSize: String, Codable, CaseIterable, Identifiable {
    case normal, large
    var id: String { rawValue }
    var title: String { self == .normal ? "Normal" : "Grande" }
    /// Escala de la instantánea: a más escala, letras más grandes en la misma imagen.
    var scale: Double { self == .normal ? 1.5 : 2.0 }
}

struct MapSettings: Codable, Equatable {
    /// Mapa de calles de Apple. Si está apagado se dibuja solo la ruta.
    var streets = true
    var style: MapStyle = .standard
    var threeD = true
    var traffic = true
    var northUp = false
    var labels: MapLabelSize = .large
    /// Multiplicador del zoom automático (menos = más cerca).
    var zoom: Double = 1.0
    var routeStyle: RouteStyle = .standard
    /// Zoom según la velocidad y antes de cada giro; apagado, distancia fija.
    var autoZoom = true

    static let zoomRange = 0.6...1.6

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MapSettings()
        streets = (try? c.decode(Bool.self, forKey: .streets)) ?? d.streets
        style = (try? c.decode(MapStyle.self, forKey: .style)) ?? d.style
        threeD = (try? c.decode(Bool.self, forKey: .threeD)) ?? d.threeD
        traffic = (try? c.decode(Bool.self, forKey: .traffic)) ?? d.traffic
        northUp = (try? c.decode(Bool.self, forKey: .northUp)) ?? d.northUp
        labels = (try? c.decode(MapLabelSize.self, forKey: .labels)) ?? d.labels
        let z = (try? c.decode(Double.self, forKey: .zoom)) ?? d.zoom
        zoom = min(max(z, MapSettings.zoomRange.lowerBound), MapSettings.zoomRange.upperBound)
        routeStyle = (try? c.decode(RouteStyle.self, forKey: .routeStyle)) ?? d.routeStyle
        autoZoom = (try? c.decode(Bool.self, forKey: .autoZoom)) ?? d.autoZoom
    }

    /// Lo que cambia el aspecto de la imagen (para descartar instantáneas viejas).
    func styleKey(night: Bool) -> String {
        "\(style.rawValue)-\(traffic)-\(labels.rawValue)-\(night ? "n" : "d")"
    }
}
