// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.7: mapa propio de OpenStreetMap guardado en el iPhone. Lee el archivo .cfmap que genera
// Tools/OSM/build_cfmap.py (formato descrito allí): se abre mapeado en memoria y cada cuadro de
// 0,01° (unos 1,1 km) se descomprime solo al usarlo. No necesita internet ni la tarjeta gráfica,
// así que sirve igual con el iPhone bloqueado. Datos © OpenStreetMap (ODbL).
import Foundation
import Compression

/// Punto en millonésimas de grado (x = longitud, y = latitud). Enteros: el mismo nudo de
/// OpenStreetMap tiene exactamente las mismas coordenadas en todos los cuadros.
struct OSMPoint: Hashable {
    var x: Int32
    var y: Int32
    var geo: GeoPoint { GeoPoint(lat: Double(y) / 1e6, lon: Double(x) / 1e6) }
    init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
    init(_ g: GeoPoint) {
        x = Int32((g.lon * 1e6).rounded())
        y = Int32((g.lat * 1e6).rounded())
    }
}

struct OSMRoad {
    /// 1 servicio o terracería, 2 residencial, 3 terciaria, 4 secundaria, 5 primaria, 6 troncal, 7 autopista.
    var cls: Int
    var roundabout: Bool
    var link: Bool
    /// 0 doble sentido, 1 solo en el sentido de los puntos, 2 solo al revés.
    var oneway: Int
    var bridge: Bool
    var tunnel: Bool
    var name: UInt32
    var points: [OSMPoint]
}

struct OSMArea {
    /// 1 parque o bosque, 2 agua.
    var kind: Int
    var rings: [[OSMPoint]]
}

struct OSMLine {
    /// 1 río o canal, 2 arroyo.
    var kind: Int
    var points: [OSMPoint]
}

final class OSMTile {
    let row: Int
    let col: Int
    let roads: [OSMRoad]
    let areas: [OSMArea]
    let lines: [OSMLine]
    init(row: Int, col: Int, roads: [OSMRoad], areas: [OSMArea], lines: [OSMLine]) {
        self.row = row
        self.col = col
        self.roads = roads
        self.areas = areas
        self.lines = lines
    }
}

/// Un lugar para buscar sin internet (pueblo, colonia, gasolinera, calle con nombre…).
struct OSMPlace {
    var point: OSMPoint
    var name: UInt32
    var kind: Int

    var kindTitle: String {
        switch kind {
        case 1: return "Ciudad"
        case 2: return "Pueblo"
        case 3: return "Aldea"
        case 4, 5: return "Zona o colonia"
        case 6: return "Lugar"
        case 10: return "Gasolinera"
        case 11: return "Hospital o clínica"
        case 12: return "Policía"
        case 13: return "Universidad"
        case 14: return "Escuela"
        case 15: return "Mercado"
        case 16: return "Banco"
        case 17: return "Restaurante o café"
        case 18: return "Farmacia"
        case 19: return "Parqueo"
        case 20: return "Iglesia"
        case 21: return "Centro comercial"
        case 22: return "Supermercado"
        case 23: return "Tienda de motos"
        case 24: return "Taller"
        case 25: return "Ferretería"
        case 30: return "Calle"
        default: return "Lugar"
        }
    }
}

final class OSMMapData {
    static let noName = UInt32.max
    /// El mapa de Guatemala que viene con la app (nil si no está en el paquete).
    static let shared: OSMMapData? = {
        guard let url = Bundle.main.url(forResource: "Guatemala", withExtension: "cfmap") else { return nil }
        return OSMMapData(url: url)
    }()
    /// Para las pruebas: otro archivo en lugar del de la app.
    static var override: OSMMapData?
    static var current: OSMMapData? { override ?? shared }

    let data: Data
    let tileCount: Int
    let nameCount: Int
    let placeCount: Int
    /// Origen de la rejilla y tamaño de cada cuadro, en millonésimas de grado.
    let lon0: Int
    let lat0: Int
    let step: Int
    let cols: Int
    let rows: Int
    /// Fecha de los datos de OpenStreetMap.
    let date: Date
    private let posNames: Int
    private let posPlaces: Int
    private let posIndex: Int
    private let posData: Int
    private let nameText: Int

    private let lock = NSLock()
    private var cache: [Int: OSMTile] = [:]
    private var missing: Set<Int> = []
    private var order: [Int] = []
    /// Cuadros descomprimidos que se guardan (los más recientes). Unos 30 KB cada uno.
    static let cacheLimit = 160

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        self.init(data: d)
    }

    init?(data d: Data) {
        guard d.count > 84, d.prefix(8) == Data("CFMAP1\0\0".utf8) else { return nil }
        data = d
        func u32(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.littleEndian) }
        func i32(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int32.self) }.littleEndian) }
        func u64(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt64.self) }.littleEndian) }
        guard u32(8) == 1 else { return nil }
        tileCount = u32(12)
        nameCount = u32(16)
        placeCount = u32(20)
        lon0 = i32(24)
        lat0 = i32(28)
        step = i32(32)
        cols = u32(36)
        rows = u32(40)
        date = Date(timeIntervalSince1970: TimeInterval(u64(44)))
        posNames = u64(52)
        posPlaces = u64(60)
        posIndex = u64(68)
        posData = u64(76)
        nameText = posNames + 4 + 4 * nameCount
        guard step > 0, posData <= d.count, posIndex + 16 * tileCount <= d.count else { return nil }
    }

    // MARK: - Lectura

    private func u32(_ o: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.littleEndian
    }

    func name(_ id: UInt32) -> String {
        guard id != OSMMapData.noName, Int(id) < nameCount else { return "" }
        let a = nameText + Int(u32(posNames + 4 + 4 * Int(id)))
        let b = Int(id) + 1 < nameCount ? nameText + Int(u32(posNames + 4 + 4 * (Int(id) + 1))) : posPlaces
        guard a <= b, b <= data.count else { return "" }
        return String(decoding: data[data.startIndex + a ..< data.startIndex + b], as: UTF8.self)
    }

    func place(_ i: Int) -> OSMPlace {
        let o = posPlaces + 16 * i
        let x = Int32(bitPattern: u32(o))
        let y = Int32(bitPattern: u32(o + 4))
        let n = u32(o + 8)
        let k = Int(data[data.startIndex + o + 12])
        return OSMPlace(point: OSMPoint(x: x, y: y), name: n, kind: k)
    }

    /// Fila y columna absolutas (en cuadros desde 0°) de un punto.
    func cell(of p: OSMPoint) -> (row: Int, col: Int) {
        (Int(floor(Double(p.y) / Double(step))), Int(floor(Double(p.x) / Double(step))))
    }

    /// El cuadro de esa fila y columna absolutas, o nil si no hay datos.
    func tile(row: Int, col: Int) -> OSMTile? {
        let r = row - Int(floor(Double(lat0) / Double(step)))
        let c = col - Int(floor(Double(lon0) / Double(step)))
        guard r >= 0, r < rows, c >= 0, c < cols else { return nil }
        let key = r * cols + c
        lock.lock()
        if let t = cache[key] {
            lock.unlock()
            return t
        }
        if missing.contains(key) {
            lock.unlock()
            return nil
        }
        lock.unlock()
        let t = load(key: key, row: row, col: col)
        lock.lock()
        if let t = t {
            cache[key] = t
            order.append(key)
            if order.count > OSMMapData.cacheLimit {
                let old = order.removeFirst()
                cache[old] = nil
            }
        } else {
            missing.insert(key)
        }
        lock.unlock()
        return t
    }

    /// Un cuadro sin pasar por la caché (para armar rutas: se leen muchos una sola vez), solo con
    /// las calles de clase `minClass` o más.
    func tileUncached(row: Int, col: Int, minClass: Int) -> OSMTile? {
        let r = row - Int(floor(Double(lat0) / Double(step)))
        let c = col - Int(floor(Double(lon0) / Double(step)))
        guard r >= 0, r < rows, c >= 0, c < cols else { return nil }
        lock.lock()
        let cached = cache[r * cols + c]
        lock.unlock()
        let t = cached ?? load(key: r * cols + c, row: row, col: col)
        guard let tile = t else { return nil }
        if minClass <= 1 { return tile }
        return OSMTile(row: row, col: col, roads: tile.roads.filter { $0.cls >= minClass }, areas: [], lines: [])
    }

    /// Los cuadros que tocan la caja (millonésimas de grado).
    func tiles(minX: Int, minY: Int, maxX: Int, maxY: Int) -> [OSMTile] {
        var out: [OSMTile] = []
        let r0 = Int(floor(Double(minY) / Double(step)))
        let r1 = Int(floor(Double(maxY) / Double(step)))
        let c0 = Int(floor(Double(minX) / Double(step)))
        let c1 = Int(floor(Double(maxX) / Double(step)))
        guard r1 - r0 < 400, c1 - c0 < 400 else { return [] }
        for r in r0...r1 {
            for c in c0...c1 {
                if let t = tile(row: r, col: c) { out.append(t) }
            }
        }
        return out
    }

    /// Búsqueda binaria en el índice (ordenado por clave).
    private func entry(_ key: Int) -> (offset: Int, size: Int, raw: Int)? {
        var lo = 0
        var hi = tileCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let o = posIndex + 16 * mid
            let k = Int(u32(o))
            if k == key { return (Int(u32(o + 4)), Int(u32(o + 8)), Int(u32(o + 12))) }
            if k < key { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    private func load(key: Int, row: Int, col: Int) -> OSMTile? {
        guard let e = entry(key), posData + e.offset + e.size <= data.count, e.raw > 6 else { return nil }
        var raw = [UInt8](repeating: 0, count: e.raw)
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.baseAddress else { return 0 }
            return compression_decode_buffer(&raw, e.raw, base.advanced(by: posData + e.offset).assumingMemoryBound(to: UInt8.self),
                                             e.size, nil, COMPRESSION_ZLIB)
        }
        guard written == e.raw else { return nil }
        return OSMMapData.parse(raw, row: row, col: col, step: step)
    }

    static func parse(_ b: [UInt8], row: Int, col: Int, step: Int) -> OSMTile? {
        var p = 0
        func u8() -> Int {
            defer { p += 1 }
            return Int(b[p])
        }
        func u16() -> Int {
            defer { p += 2 }
            return Int(b[p]) | Int(b[p + 1]) << 8
        }
        func u32() -> UInt32 {
            defer { p += 4 }
            return UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24
        }
        func i16() -> Int32 {
            defer { p += 2 }
            return Int32(Int16(bitPattern: UInt16(b[p]) | UInt16(b[p + 1]) << 8))
        }
        let ox = Int32(col * step)
        let oy = Int32(row * step)
        func points(_ n: Int) -> [OSMPoint]? {
            guard p + 4 * n <= b.count else { return nil }
            var out = [OSMPoint]()
            out.reserveCapacity(n)
            var x = ox
            var y = oy
            for _ in 0..<n {
                x += i16()
                y += i16()
                out.append(OSMPoint(x: x, y: y))
            }
            return out
        }
        guard b.count >= 6 else { return nil }
        let nr = u16()
        let na = u16()
        let nl = u16()
        var roads: [OSMRoad] = []
        roads.reserveCapacity(nr)
        for _ in 0..<nr {
            guard p + 8 <= b.count else { return nil }
            let flags = u8()
            let dir = u8()
            let name = u32()
            let n = u16()
            guard let pts = points(n) else { return nil }
            roads.append(OSMRoad(cls: flags & 0x0F, roundabout: flags & 0x10 != 0, link: flags & 0x20 != 0,
                                 oneway: dir & 3, bridge: dir & 4 != 0, tunnel: dir & 8 != 0, name: name, points: pts))
        }
        var areas: [OSMArea] = []
        for _ in 0..<na {
            guard p + 3 <= b.count else { return nil }
            let kind = u8()
            let nrings = u16()
            var rings: [[OSMPoint]] = []
            for _ in 0..<nrings {
                guard p + 2 <= b.count else { return nil }
                let n = u16()
                guard let pts = points(n) else { return nil }
                rings.append(pts)
            }
            areas.append(OSMArea(kind: kind, rings: rings))
        }
        var lines: [OSMLine] = []
        for _ in 0..<nl {
            guard p + 3 <= b.count else { return nil }
            let kind = u8()
            let n = u16()
            guard let pts = points(n) else { return nil }
            lines.append(OSMLine(kind: kind, points: pts))
        }
        guard p == b.count else { return nil }
        return OSMTile(row: row, col: col, roads: roads, areas: areas, lines: lines)
    }
}
