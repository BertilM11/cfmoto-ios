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
    /// 0.8.1: terracería o tierra (pista, grava, lastre…).
    var unpaved: Bool = false
    /// 0.8.1: velocidad máxima en km/h (0 si OpenStreetMap no la tiene).
    var maxspeed: Int = 0
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

/// 0.9.0: los edificios de un cuadro, en arreglos planos (pocas reservas de memoria):
/// el edificio i va de `starts[i]` a `starts[i + 1]` en `xs`/`ys` (millonésimas de grado).
final class OSMBuildingTile {
    let row: Int
    let col: Int
    let xs: [Int32]
    let ys: [Int32]
    let starts: [Int32]
    var count: Int { max(0, starts.count - 1) }
    init(row: Int, col: Int, xs: [Int32], ys: [Int32], starts: [Int32]) {
        self.row = row
        self.col = col
        self.xs = xs
        self.ys = ys
        self.starts = starts
    }
}

/// Un lugar para buscar sin internet (pueblo, colonia, gasolinera, calle con nombre…).
struct OSMPlace {
    var point: OSMPoint
    var name: UInt32
    var kind: Int
    /// Otro nombre (alt_name…) del lugar anterior de la lista.
    var alias = false
    /// Índice del municipio (o departamento) al que pertenece; -1 si no se sabe.
    var admin = -1

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
        case 26: return "Hotel"
        case 27: return "Lugar turístico"
        case 28: return "Terminal de buses"
        case 29: return "Estadio"
        case 30: return "Calle"
        case 31: return "Municipalidad"
        case 32: return "Aeropuerto"
        case 33: return "Negocio o lugar"
        case 34: return "Residencial o colonia"
        case 40: return "Municipio"
        case 41: return "Departamento"
        default: return "Lugar"
        }
    }
}

final class OSMMapData {
    static let noName = UInt32.max
    /// El mapa de Guatemala: el descargado desde la app (0.8.1) si es válido y no es más viejo
    /// que el que viene con la app; si no, el de la app. Se elige al abrir la app.
    static let shared: OSMMapData? = {
        let bundled = Bundle.main.url(forResource: "Guatemala", withExtension: "cfmap").flatMap { OSMMapData(url: $0) }
        if let downloaded = OSMMapData(url: downloadedURL), downloaded.version >= 2,
           bundled == nil || downloaded.date >= bundled!.date {
            usingDownloaded = true
            return downloaded
        }
        return bundled
    }()
    /// 0.8.1: el mapa en uso es uno descargado desde la app.
    private(set) static var usingDownloaded = false
    /// 0.8.1: dónde se guarda el mapa descargado.
    static var downloadedURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mapas", isDirectory: true).appendingPathComponent("Guatemala.cfmap")
    }
    /// Para las pruebas: otro archivo en lugar del de la app.
    static var override: OSMMapData?
    static var current: OSMMapData? { override ?? shared }

    let data: Data
    /// 1 o 2 (la 2 trae departamentos, municipios y el municipio de cada lugar).
    let version: Int
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

    /// 0.9.0: sección de edificios (si el archivo la trae).
    private let posBuildingIndex: Int
    let buildingTileCount: Int
    private let buildingQuantum: Int
    var hasBuildings: Bool { buildingTileCount > 0 }

    private let lock = NSLock()
    private var cache: [Int: OSMTile] = [:]
    private var buildingCache: [Int64: OSMBuildingTile] = [:]
    private var buildingOrder: [Int64] = []
    private var buildingMissing: Set<Int64> = []
    static let buildingCacheLimit = 64
    private var missing: Set<Int> = []
    private var order: [Int] = []
    /// Cuadros descomprimidos que se guardan (los más recientes). Unos 30 KB cada uno.
    static let cacheLimit = 160

    /// 0.9.0: deja solo los `keep` cuadros más recientes (aviso de memoria o segundo plano).
    func trimCache(keep: Int) {
        lock.lock()
        while order.count > keep {
            let old = order.removeFirst()
            cache[old] = nil
        }
        missing.removeAll()
        buildingCache.removeAll()
        buildingOrder.removeAll()
        buildingMissing.removeAll()
        lock.unlock()
    }

    convenience init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        self.init(data: d)
    }

    init?(data d: Data) {
        guard d.count > 84, d.prefix(8) == Data("CFMAP1\0\0".utf8) else { return nil }
        data = d
        func u32(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.littleEndian) }
        func i32(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int32.self) }.littleEndian) }
        func u64(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt64.self) }.littleEndian) }
        version = u32(8)
        guard version == 1 || version == 2 else { return nil }
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
        // 0.9.0: cola «CFBLD2\0\0» + posición del índice de edificios (u64) + cuadros (u32) + paso (u32).
        var bIndex = 0, bCount = 0, bq = 0
        let dataStart = u64(76)
        if d.count >= dataStart + 24, d.subdata(in: (d.count - 24)..<(d.count - 16)) == Data("CFBLD2\0\0".utf8) {
            let pi = u64(d.count - 16)
            let n = u32(d.count - 8)
            let q = u32(d.count - 4)
            if pi >= dataStart, q > 0, pi + 20 * n <= d.count - 24 {
                bIndex = pi
                bCount = n
                bq = q
            }
        }
        posBuildingIndex = bIndex
        buildingTileCount = bCount
        buildingQuantum = bq
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
        var owner = -1
        if version >= 2 {
            let v = Int(data[data.startIndex + o + 14]) | Int(data[data.startIndex + o + 15]) << 8
            if v != 0xFFFF { owner = v }
        }
        return OSMPlace(point: OSMPoint(x: x, y: y), name: n, kind: k & 0x7F, alias: k & 0x80 != 0, admin: owner)
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
        if let tile = cached {
            if minClass <= 1 { return tile }
            return OSMTile(row: row, col: col, roads: tile.roads.filter { $0.cls >= minClass }, areas: [], lines: [])
        }
        // Solo las calles que sirven (sin parques, agua ni las calles menores): más rápido.
        return load(key: r * cols + c, row: row, col: col, roadsFrom: max(1, minClass))
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

    private func load(key: Int, row: Int, col: Int, roadsFrom minClass: Int? = nil) -> OSMTile? {
        guard let e = entry(key), posData + e.offset + e.size <= data.count, e.raw > 6 else { return nil }
        var raw = [UInt8](repeating: 0, count: e.raw)
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.baseAddress else { return 0 }
            return compression_decode_buffer(&raw, e.raw, base.advanced(by: posData + e.offset).assumingMemoryBound(to: UInt8.self),
                                             e.size, nil, COMPRESSION_ZLIB)
        }
        guard written == e.raw else { return nil }
        return OSMMapData.parse(raw, row: row, col: col, step: step, roadsFrom: minClass)
    }

    // MARK: - Edificios (0.9.0)

    /// Los edificios del cuadro de esa fila y columna absolutas (nil si no hay).
    func buildings(row: Int, col: Int) -> OSMBuildingTile? {
        guard buildingTileCount > 0 else { return nil }
        let key = Int64(row) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: col)))
        lock.lock()
        if let t = buildingCache[key] {
            lock.unlock()
            return t
        }
        if buildingMissing.contains(key) {
            lock.unlock()
            return nil
        }
        lock.unlock()
        let t = loadBuildings(row: row, col: col)
        lock.lock()
        if let t = t {
            buildingCache[key] = t
            buildingOrder.append(key)
            if buildingOrder.count > OSMMapData.buildingCacheLimit {
                buildingCache[buildingOrder.removeFirst()] = nil
            }
        } else {
            buildingMissing.insert(key)
        }
        lock.unlock()
        return t
    }

    /// Los cuadros de edificios que tocan la caja (millonésimas de grado).
    func buildingTiles(minX: Int, minY: Int, maxX: Int, maxY: Int) -> [OSMBuildingTile] {
        guard buildingTileCount > 0 else { return [] }
        let r0 = Int(floor(Double(minY) / Double(step)))
        let r1 = Int(floor(Double(maxY) / Double(step)))
        let c0 = Int(floor(Double(minX) / Double(step)))
        let c1 = Int(floor(Double(maxX) / Double(step)))
        guard r1 - r0 < 40, c1 - c0 < 40 else { return [] }
        var out: [OSMBuildingTile] = []
        for r in r0...r1 {
            for c in c0...c1 {
                if let t = buildings(row: r, col: c) { out.append(t) }
            }
        }
        return out
    }

    private func loadBuildings(row: Int, col: Int) -> OSMBuildingTile? {
        // Búsqueda binaria por (fila, columna) en el índice de 20 bytes por cuadro.
        func i32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int32.self) }.littleEndian) }
        func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.littleEndian) }
        var lo = 0
        var hi = buildingTileCount - 1
        var found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let o = posBuildingIndex + 20 * mid
            let r = i32(o)
            let c = i32(o + 4)
            if r == row && c == col {
                found = o
                break
            }
            if r < row || (r == row && c < col) { lo = mid + 1 } else { hi = mid - 1 }
        }
        guard found >= 0 else { return nil }
        let offset = u32(found + 8)
        let size = u32(found + 12)
        let rawLen = u32(found + 16)
        let base = posBuildingIndex + 20 * buildingTileCount
        guard rawLen > 0, rawLen < 64 << 20, base + offset + size <= data.count - 24 else { return nil }
        var raw = [UInt8](repeating: 0, count: rawLen)
        let written = data.withUnsafeBytes { src -> Int in
            guard let b = src.baseAddress else { return 0 }
            return compression_decode_buffer(&raw, rawLen, b.advanced(by: base + offset).assumingMemoryBound(to: UInt8.self),
                                             size, nil, COMPRESSION_ZLIB)
        }
        guard written == rawLen else { return nil }
        return OSMMapData.parseBuildings(raw, row: row, col: col, step: step, quantum: buildingQuantum)
    }

    /// Lee los edificios de un cuadro descomprimido (formato en Tools/OSM/build_cfmap.py).
    static func parseBuildings(_ b: [UInt8], row: Int, col: Int, step: Int, quantum q: Int) -> OSMBuildingTile? {
        var p = 0
        var ok = true
        func varint() -> Int {
            var v = 0
            var shift = 0
            while p < b.count {
                let byte = Int(b[p])
                p += 1
                v |= (byte & 0x7F) << shift
                if byte & 0x80 == 0 { return v }
                shift += 7
                if shift > 56 { break }
            }
            ok = false
            return 0
        }
        func zigzag() -> Int {
            let v = varint()
            return (v >> 1) ^ -(v & 1)
        }
        let n = varint()
        guard ok, n < 1_000_000 else { return nil }
        var xs: [Int32] = []
        var ys: [Int32] = []
        var starts: [Int32] = [0]
        xs.reserveCapacity(n * 6)
        ys.reserveCapacity(n * 6)
        starts.reserveCapacity(n + 1)
        let unitStep = step / max(1, q)
        var px = col * unitStep
        var py = row * unitStep
        for _ in 0..<n {
            let code = varint()
            guard ok, code < 10_000 else { return nil }
            px += zigzag()
            py += zigzag()
            if code == 0 {
                // Rectángulo: lado p0→p1 y ancho con signo hacia la derecha (igual que el armador).
                let ex = zigzag()
                let ey = zigzag()
                let w = zigzag()
                guard ok else { return nil }
                let len = (Double(ex * ex + ey * ey)).squareRoot()
                guard len > 0 else { return nil }
                func rint(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }
                let x1 = px + ex
                let y1 = py + ey
                let x2 = x1 + rint(Double(w * ey) / len)
                let y2 = y1 - rint(Double(w * ex) / len)
                let x3 = px + (x2 - x1)
                let y3 = py + (y2 - y1)
                for (x, y) in [(px, py), (x1, y1), (x2, y2), (x3, y3)] {
                    xs.append(Int32(x * q))
                    ys.append(Int32(y * q))
                }
            } else {
                let count = code + 2
                var lx = px
                var ly = py
                xs.append(Int32(lx * q))
                ys.append(Int32(ly * q))
                for _ in 1..<count {
                    lx += zigzag()
                    ly += zigzag()
                    xs.append(Int32(lx * q))
                    ys.append(Int32(ly * q))
                }
                guard ok else { return nil }
            }
            starts.append(Int32(xs.count))
        }
        guard p == b.count else { return nil }
        return OSMBuildingTile(row: row, col: col, xs: xs, ys: ys, starts: starts)
    }

    /// Lee un cuadro descomprimido. Con `roadsFrom`, solo las calles de esa clase o más.
    static func parse(_ b: [UInt8], row: Int, col: Int, step: Int, roadsFrom minClass: Int? = nil) -> OSMTile? {
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
            if let least = minClass, flags & 0x0F < least {
                guard p + 4 * n <= b.count else { return nil }
                p += 4 * n
                continue
            }
            guard let pts = points(n) else { return nil }
            roads.append(OSMRoad(cls: flags & 0x0F, roundabout: flags & 0x10 != 0, link: flags & 0x20 != 0,
                                 oneway: dir & 3, bridge: dir & 4 != 0, tunnel: dir & 8 != 0, name: name, points: pts,
                                 unpaved: flags & 0x40 != 0, maxspeed: ((dir >> 4) & 0x0F) * 10))
        }
        if minClass != nil {
            return OSMTile(row: row, col: col, roads: roads, areas: [], lines: [])
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
