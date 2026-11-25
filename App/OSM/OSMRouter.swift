// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.7: rutas calculadas en el iPhone con el mapa de OpenStreetMap: sin internet, también con el
// iPhone bloqueado (solo CPU). El grafo se arma con los cuadros entre el origen y el destino:
// todas las calles cerca de los extremos y solo las principales en medio. A* por tiempo, con los
// sentidos de las calles, y maniobras en español (giros, rotondas, salidas, llegada).
// Sin tráfico en vivo: el tiempo sale de una velocidad típica por tipo de calle.
import Foundation

/// Una ruta calculada.
struct OSMRoute {
    var points: [GeoPoint]
    var distance: Double
    /// Segundos previstos (sin tráfico).
    var time: Double
    var maneuvers: [(at: Double, kind: ManeuverKind, text: String)]
    /// Las calles principales, para distinguir rutas («por Avenida Reforma y 14 Calle»).
    var summary: String
    /// Tramos usados (para buscar alternativas distintas).
    var edges: [Int]
    /// 0.8.1: velocidad máxima por tramos de la ruta: desde qué metro rige y cuántos km/h
    /// (0 = OpenStreetMap no la tiene).
    var speedLimits: [(at: Double, kmh: Int)] = []
    /// 0.8.1: metros de terracería en la ruta.
    var unpavedMeters: Double = 0
}

/// 0.8.1: preferencias para elegir la ruta.
struct RouteOptions: Equatable {
    /// Evitar terracería (se usa solo si no hay otra forma razonable).
    var avoidUnpaved = false
    /// Evitar autopistas y carreteras troncales.
    var avoidHighways = false

    /// Cuánto «pesa» un tramo según las preferencias (1 = normal).
    func factor(cls: Int, unpaved: Bool) -> Double {
        var f = 1.0
        if avoidUnpaved && unpaved { f *= 4 }
        if avoidHighways && cls >= 6 { f *= 2.5 }
        return f
    }
}

final class OSMRouter {
    let map: OSMMapData
    /// 0.8.1: preferencias de ruta.
    var options = RouteOptions()
    /// Tamaño del último grafo (para el diagnóstico y las pruebas de rendimiento). `wide`: hizo
    /// falta el grafo amplio (la ruta da un rodeo grande, como a Petén).
    private(set) var lastStats = (tiles: 0, nodes: 0, edges: 0, wide: false)

    init(map: OSMMapData) {
        self.map = map
    }

    /// Velocidad típica (m/s) por clase de calle.
    static func speed(_ cls: Int, roundabout: Bool) -> Double {
        if roundabout { return 25 / 3.6 }
        switch cls {
        case 7: return 80 / 3.6
        case 6: return 65 / 3.6
        case 5: return 50 / 3.6
        case 4: return 40 / 3.6
        case 3: return 35 / 3.6
        case 2: return 25 / 3.6
        default: return 15 / 3.6
        }
    }

    // MARK: - Grafo

    /// Un tramo entre dos nudos. Compacto: en rutas largas hay cientos de miles.
    struct Edge {
        var a: Int32
        var b: Int32
        var len: Float
        var name: UInt32
        var clsByte: UInt8
        var roundabout: Bool
        var link: Bool
        var forward: Bool
        var backward: Bool
        /// 0.8.1: terracería y velocidad máxima (decenas de km/h; 0 si no se sabe).
        var unpaved: Bool = false
        var limitTens: UInt8 = 0

        var cls: Int { Int(clsByte) }
        var length: Double {
            get { Double(len) }
            set { len = Float(newValue) }
        }
    }

    final class Graph {
        var index: [OSMPoint: Int32] = [:]
        var nodes: [OSMPoint] = []
        var edges: [Edge] = []
        /// Tramos de cada nudo como lista enlazada (sin un arreglo por nudo: menos memoria).
        var head: [Int32] = []
        var nextInc: [Int32] = []
        var incEdge: [Int32] = []
        private var seen = Set<Int64>()

        func node(_ p: OSMPoint) -> Int32 {
            if let i = index[p] { return i }
            let i = Int32(nodes.count)
            index[p] = i
            nodes.append(p)
            head.append(-1)
            return i
        }

        private func link(_ n: Int32, _ edge: Int32) {
            incEdge.append(edge)
            nextInc.append(head[Int(n)])
            head[Int(n)] = Int32(incEdge.count - 1)
        }

        private func unlink(_ n: Int32, _ edge: Int32) {
            var prev: Int32 = -1
            var i = head[Int(n)]
            while i >= 0 {
                if incEdge[Int(i)] == edge {
                    if prev < 0 { head[Int(n)] = nextInc[Int(i)] } else { nextInc[Int(prev)] = nextInc[Int(i)] }
                    return
                }
                prev = i
                i = nextInc[Int(i)]
            }
        }

        /// Los tramos que tocan el nudo `n` (para las maniobras; la búsqueda recorre la lista).
        func incident(_ n: Int32) -> [Int32] {
            var out: [Int32] = []
            var i = head[Int(n)]
            while i >= 0 {
                out.append(incEdge[Int(i)])
                i = nextInc[Int(i)]
            }
            return out
        }

        func add(_ p: OSMPoint, _ q: OSMPoint, road: OSMRoad) {
            guard p != q else { return }
            let a = node(p)
            let b = node(q)
            let key = Int64(min(a, b)) << 32 | Int64(max(a, b))
            guard seen.insert(key).inserted else { return }
            let e = Edge(a: a, b: b, len: Float(p.geo.distance(to: q.geo)), name: road.name, clsByte: UInt8(max(0, min(255, road.cls))),
                         roundabout: road.roundabout, link: road.link, forward: road.oneway != 2, backward: road.oneway != 1,
                         unpaved: road.unpaved, limitTens: UInt8(max(0, min(15, road.maxspeed / 10))))
            let id = Int32(edges.count)
            edges.append(e)
            link(a, id)
            link(b, id)
        }

        /// Parte el tramo `e` en el punto `p` (que queda como nudo nuevo) y devuelve el nudo.
        func split(_ id: Int, at p: OSMPoint) -> Int32 {
            let e = edges[id]
            if nodes[Int(e.a)] == p { return e.a }
            if nodes[Int(e.b)] == p { return e.b }
            let m = node(p)
            var first = e
            first.b = m
            first.length = nodes[Int(e.a)].geo.distance(to: p.geo)
            var second = e
            second.a = m
            second.length = p.geo.distance(to: nodes[Int(e.b)].geo)
            edges[id] = first
            link(m, Int32(id))
            unlink(e.b, Int32(id))
            let id2 = Int32(edges.count)
            edges.append(second)
            link(m, id2)
            link(e.b, id2)
            return m
        }
    }

    /// Arma el grafo para ir de `a` a `b`. Normal: una caja con hasta 25 km de margen y las calles
    /// terciarias o mayores en medio. Amplio: casi todo el país con las carreteras principales en
    /// medio, para rutas que dan un rodeo grande (de la capital a Petén se va por Río Dulce).
    func graph(from a: GeoPoint, to b: GeoPoint, wide: Bool = false) -> Graph {
        let g = Graph()
        let direct = a.distance(to: b)
        let margin = wide ? max(60_000, min(260_000, direct * 0.9)) : max(2500, min(25_000, direct * 0.25))
        let pa = OSMPoint(a)
        let pb = OSMPoint(b)
        let dLat = Int(margin / 110_574 * 1e6)
        let dLon = Int(margin / (111_320 * cos(a.lat * .pi / 180)) * 1e6)
        let minX = Int(min(pa.x, pb.x)) - dLon
        let maxX = Int(max(pa.x, pb.x)) + dLon
        let minY = Int(min(pa.y, pb.y)) - dLat
        let maxY = Int(max(pa.y, pb.y)) + dLat
        // Cerca de los extremos (o en rutas cortas) van todas las calles; en medio, las principales.
        let detail = max(4000, min(12_000, direct * 0.3))
        // Solo dentro del mapa (fuera no hay cuadros).
        let rowMin = Int(floor(Double(map.lat0) / Double(map.step)))
        let colMin = Int(floor(Double(map.lon0) / Double(map.step)))
        let r0 = max(rowMin, Int(floor(Double(minY) / Double(map.step))))
        let r1 = min(rowMin + map.rows - 1, Int(floor(Double(maxY) / Double(map.step))))
        let c0 = max(colMin, Int(floor(Double(minX) / Double(map.step))))
        let c1 = min(colMin + map.cols - 1, Int(floor(Double(maxX) / Double(map.step))))
        let middle = wide ? 4 : 3
        guard r1 >= r0, c1 >= c0, (r1 - r0 + 1) * (c1 - c0 + 1) <= 400_000 else { return g }
        let half = Double(map.step) / 2
        for r in r0...r1 {
            for c in c0...c1 {
                let center = GeoPoint(lat: (Double(r * map.step) + half) / 1e6, lon: (Double(c * map.step) + half) / 1e6)
                let near = direct < 15_000 || center.distance(to: a) < detail || center.distance(to: b) < detail
                guard let t = map.tileUncached(row: r, col: c, minClass: near ? 1 : middle) else { continue }
                lastStats.tiles += 1
                for road in t.roads {
                    for i in 0..<(road.points.count - 1) {
                        g.add(road.points[i], road.points[i + 1], road: road)
                    }
                }
            }
        }
        return g
    }

    // MARK: - Ruta

    /// Hasta 1 + `alternatives` rutas, la más rápida primero. `heading`: rumbo actual (para no
    /// proponer dar la vuelta al recalcular).
    func routes(from a: GeoPoint, to b: GeoPoint, alternatives: Int = 2, heading: Double? = nil, wide: Bool = false) -> [OSMRoute] {
        let found = attempt(from: a, to: b, alternatives: alternatives, heading: heading, wide: wide)
        if found.isEmpty && !wide && a.distance(to: b) > 20_000 {
            // En la caja normal no hay camino (el que hay da un rodeo): con el grafo amplio.
            return attempt(from: a, to: b, alternatives: alternatives, heading: heading, wide: true)
        }
        return found
    }

    private func attempt(from a: GeoPoint, to b: GeoPoint, alternatives: Int, heading: Double?, wide: Bool) -> [OSMRoute] {
        lastStats = (0, 0, 0, wide)
        let g = graph(from: a, to: b, wide: wide)
        lastStats.nodes = g.nodes.count
        lastStats.edges = g.edges.count
        guard !g.edges.isEmpty, let s = snap(g, a), let t = snap(g, b) else { return [] }
        let start = g.split(s.edge, at: s.point)
        let end = g.split(t.edge, at: t.point)
        guard start != end else { return [] }
        var penalty: [Int: Double] = [:]
        var out: [OSMRoute] = []
        for round in 0...max(0, alternatives) {
            guard let path = search(g, from: start, to: end, penalty: penalty, heading: round == 0 ? heading : heading) else { break }
            let route = describe(g, path)
            if let best = out.first {
                // Una alternativa debe ser distinta (al menos un 25 % de su recorrido) y no mucho más lenta.
                let shared = Set(best.edges).intersection(route.edges)
                let sharedLength = shared.reduce(0.0) { $0 + g.edges[$1].length }
                if route.time > best.time * 1.45 { break }
                if sharedLength > route.distance * 0.75 || out.contains(where: { Set($0.edges) == Set(route.edges) }) {
                    for e in route.edges { penalty[e, default: 1] *= 1.5 }
                    continue
                }
            }
            out.append(route)
            for e in route.edges { penalty[e, default: 1] *= 1.6 }
            if out.count > alternatives { break }
        }
        return out
    }

    /// El punto de calle más cercano (a menos de 400 m), sin contar las de servicio si hay otra
    /// a menos de 40 m.
    func snap(_ g: Graph, _ p: GeoPoint) -> (edge: Int, point: OSMPoint)? {
        let kx = 111_320 * cos(p.lat * .pi / 180) / 1e6
        let ky = 110_574 / 1e6
        let px = p.lon * 1e6
        let py = p.lat * 1e6
        var best: (d: Double, edge: Int, point: OSMPoint)?
        for (i, e) in g.edges.enumerated() {
            let a = g.nodes[Int(e.a)]
            let b = g.nodes[Int(e.b)]
            let ax = (Double(a.x) - px) * kx
            let ay = (Double(a.y) - py) * ky
            let bx = (Double(b.x) - px) * kx
            let by = (Double(b.y) - py) * ky
            if min(ax, bx) > 400 || max(ax, bx) < -400 || min(ay, by) > 400 || max(ay, by) < -400 { continue }
            let dx = bx - ax
            let dy = by - ay
            let l2 = dx * dx + dy * dy
            let t = l2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / l2)) : 0
            let qx = ax + dx * t
            let qy = ay + dy * t
            var d = hypot(qx, qy)
            if e.cls <= 1 { d += 40 }
            if best == nil || d < best!.d {
                let q = OSMPoint(x: Int32((px + qx / kx).rounded()), y: Int32((py + qy / ky).rounded()))
                best = (d, i, q)
            }
        }
        guard let b = best, b.d < 440 else { return nil }
        return (b.edge, b.point)
    }

    /// A* por tiempo. Devuelve los tramos (con su sentido) de `from` a `to`.
    private func search(_ g: Graph, from: Int32, to: Int32, penalty: [Int: Double], heading: Double?) -> [(edge: Int, forward: Bool)]? {
        let n = g.nodes.count
        var cost = [Double](repeating: .infinity, count: n)
        var via = [Int32](repeating: -1, count: n)
        var viaForward = [Bool](repeating: true, count: n)
        var closed = [Bool](repeating: false, count: n)
        let goal = g.nodes[Int(to)].geo
        let vmax = 80 / 3.6
        var heap = MinHeap()
        cost[Int(from)] = 0
        heap.push(Int32(from), goal.distance(to: g.nodes[Int(from)].geo) / vmax)
        while let (u, _) = heap.pop() {
            let ui = Int(u)
            if closed[ui] { continue }
            closed[ui] = true
            if u == to { break }
            var inc = g.head[ui]
            while inc >= 0 {
                let eid = g.incEdge[Int(inc)]
                inc = g.nextInc[Int(inc)]
                let e = g.edges[Int(eid)]
                let forward = e.a == u
                if forward ? !e.forward : !e.backward { continue }
                let v = forward ? e.b : e.a
                let vi = Int(v)
                if closed[vi] { continue }
                var c = e.length / OSMRouter.speed(e.cls, roundabout: e.roundabout) * (penalty[Int(eid)] ?? 1)
                    * options.factor(cls: e.cls, unpaved: e.unpaved)
                // Al salir: no dar la vuelta si se va en otra dirección (recalcular en marcha).
                if u == from, let h = heading, h >= 0 {
                    let b = g.nodes[ui].geo.bearing(to: g.nodes[vi].geo)
                    var d = abs(b - h).truncatingRemainder(dividingBy: 360)
                    if d > 180 { d = 360 - d }
                    if d > 100 { c += 90 }
                }
                let nc = cost[ui] + c
                if nc < cost[vi] {
                    cost[vi] = nc
                    via[vi] = eid
                    viaForward[vi] = forward
                    heap.push(v, nc + goal.distance(to: g.nodes[vi].geo) / vmax)
                }
            }
        }
        guard cost[Int(to)].isFinite else { return nil }
        var out: [(Int, Bool)] = []
        var cur = to
        while cur != from {
            let eid = via[Int(cur)]
            guard eid >= 0 else { return nil }
            let e = g.edges[Int(eid)]
            out.append((Int(eid), viaForward[Int(cur)]))
            cur = viaForward[Int(cur)] ? e.a : e.b
        }
        return out.reversed()
    }

    // MARK: - Maniobras

    private func describe(_ g: Graph, _ path: [(edge: Int, forward: Bool)]) -> OSMRoute {
        var nodes: [Int32] = []
        for (i, step) in path.enumerated() {
            let e = g.edges[step.edge]
            let a = step.forward ? e.a : e.b
            let b = step.forward ? e.b : e.a
            if i == 0 { nodes.append(a) }
            nodes.append(b)
        }
        let points = nodes.map { g.nodes[Int($0)].geo }
        var cum: [Double] = [0]
        for i in 1..<points.count { cum.append(cum[i - 1] + points[i - 1].distance(to: points[i])) }
        let total = cum.last ?? 0
        var time = 0.0
        // 0.8.1: velocidad máxima por tramos (se juntan los tramos seguidos con la misma).
        var limits: [(at: Double, kmh: Int)] = []
        var unpavedMeters = 0.0
        for (i, step) in path.enumerated() {
            let e = g.edges[step.edge]
            time += e.length / OSMRouter.speed(e.cls, roundabout: e.roundabout)
            if e.unpaved { unpavedMeters += e.length }
            let kmh = Int(e.limitTens) * 10
            if limits.last?.kmh != kmh { limits.append((at: cum[i], kmh: kmh)) }
        }
        func point(at d: Double) -> GeoPoint {
            let x = max(0, min(total, d))
            var lo = 0
            var hi = cum.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if cum[mid] <= x { lo = mid } else { hi = mid }
            }
            let seg = cum[hi] - cum[lo]
            let f = seg > 0 ? (x - cum[lo]) / seg : 0
            return GeoPoint(lat: points[lo].lat + (points[hi].lat - points[lo].lat) * f,
                            lon: points[lo].lon + (points[hi].lon - points[lo].lon) * f)
        }
        func bearing(_ d0: Double, _ d1: Double) -> Double { point(at: d0).bearing(to: point(at: d1)) }
        func degree(_ node: Int32) -> Int {
            var others = Set<Int32>()
            for eid in g.incident(node) {
                let e = g.edges[Int(eid)]
                others.insert(e.a == node ? e.b : e.a)
            }
            return others.count
        }
        func name(_ id: UInt32) -> String { map.name(id) }

        var maneuvers: [(at: Double, kind: ManeuverKind, text: String)] = []
        var i = 1
        while i < path.count {
            let ein = g.edges[path[i - 1].edge]
            let eout = g.edges[path[i].edge]
            let node = nodes[i]
            let at = cum[i]
            if !ein.roundabout && eout.roundabout {
                // Rotonda: se cuentan las salidas hasta la que toca.
                var j = i
                var exits = 0
                while j < path.count && g.edges[path[j].edge].roundabout {
                    j += 1
                    if j < path.count && j < nodes.count {
                        let n = nodes[j]
                        let outs = g.incident(n).filter { id in
                            let e = g.edges[Int(id)]
                            return !e.roundabout && (e.a == n ? e.forward : e.backward)
                        }
                        if !outs.isEmpty { exits += 1 }
                    }
                }
                let exitName = j < path.count ? name(g.edges[path[j].edge].name) : ""
                let ordinal = max(1, exits)
                var text = "En la rotonda, toma la \(ordinal).ª salida"
                if !exitName.isEmpty { text += " hacia \(exitName)" }
                maneuvers.append((at, .roundabout, text))
                i = max(j, i + 1)
                continue
            }
            if ein.roundabout {
                i += 1
                continue
            }
            let delta = OSMRouter.turn(bearing(at - 25, at), bearing(at, at + 25))
            let junction = degree(node) >= 3
            let renamed = ein.name != eout.name
            let street = name(eout.name)
            var kind: ManeuverKind?
            if junction {
                if eout.link && !ein.link && abs(delta) < 40 {
                    kind = delta < 0 ? .keepLeft : .keepRight
                } else if abs(delta) >= 160 {
                    kind = .uTurn
                } else if abs(delta) >= 120 {
                    kind = delta < 0 ? .sharpLeft : .sharpRight
                } else if abs(delta) >= 45 {
                    kind = delta < 0 ? .left : .right
                } else if abs(delta) >= 22 && (renamed || ein.cls != eout.cls) {
                    kind = delta < 0 ? .slightLeft : .slightRight
                }
            }
            if let k = kind {
                var text = OSMRouter.text(k)
                if !street.isEmpty {
                    text += (k == .keepLeft || k == .keepRight) ? " hacia \(street)" : " por \(street)"
                }
                let lefts: Set<ManeuverKind> = [.slightLeft, .left, .sharpLeft, .keepLeft]
                let rights: Set<ManeuverKind> = [.slightRight, .right, .sharpRight, .keepRight]
                if let last = maneuvers.last, at - last.at < 45,
                   (lefts.contains(last.kind) && lefts.contains(k)) || (rights.contains(last.kind) && rights.contains(k)),
                   abs(OSMRouter.turn(bearing(last.at - 25, last.at), bearing(at, at + 25))) >= 150 {
                    // 0.9.0: dos giros al mismo lado casi seguidos que dejan mirando al revés (un
                    // retorno en una calle de doble vía): una sola indicación, la vuelta en U.
                    var text = OSMRouter.text(.uTurn) + " en el retorno"
                    if !street.isEmpty { text += " hacia \(street)" }
                    maneuvers[maneuvers.count - 1] = (last.at, .uTurn, text)
                } else if let last = maneuvers.last, at - last.at < 15 {
                    // Dos cruces casi juntos: se queda el primero.
                } else {
                    maneuvers.append((at, k, text))
                }
            }
            i += 1
        }
        maneuvers.append((total, .arrive, OSMRouter.text(.arrive)))

        // Resumen: las dos calles con nombre más largas de la ruta.
        var byName: [UInt32: Double] = [:]
        for step in path {
            let e = g.edges[step.edge]
            if e.name != OSMMapData.noName { byName[e.name, default: 0] += e.length }
        }
        let top = byName.sorted { $0.value > $1.value }.prefix(2).map { name($0.key) }
        let summary = top.isEmpty ? "" : "por " + top.joined(separator: " y ")
        return OSMRoute(points: points, distance: total, time: time, maneuvers: maneuvers, summary: summary,
                        edges: path.map { $0.edge }, speedLimits: limits, unpavedMeters: unpavedMeters)
    }

    /// Giro de `a` a `b` en grados (-180…180, positivo a la derecha).
    static func turn(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    static func text(_ kind: ManeuverKind) -> String {
        switch kind {
        case .depart: return "Inicia el recorrido"
        case .straight: return "Continúa recto"
        case .slightLeft: return "Gira ligeramente a la izquierda"
        case .left: return "Gira a la izquierda"
        case .sharpLeft: return "Gira cerrado a la izquierda"
        case .slightRight: return "Gira ligeramente a la derecha"
        case .right: return "Gira a la derecha"
        case .sharpRight: return "Gira cerrado a la derecha"
        case .uTurn: return "Da la vuelta en U"
        case .roundabout: return "Entra en la rotonda"
        case .keepLeft: return "Mantente a la izquierda"
        case .keepRight: return "Mantente a la derecha"
        case .arrive: return "Has llegado a tu destino"
        }
    }
}

/// Montículo de mínimos para A* (nudo, prioridad).
struct MinHeap {
    private var items: [(Int32, Double)] = []
    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ n: Int32, _ p: Double) {
        items.append((n, p))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].1 <= items[i].1 { break }
            items.swapAt(parent, i)
            i = parent
        }
    }

    mutating func pop() -> (Int32, Double)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1
                let r = l + 1
                var m = i
                if l < items.count && items[l].1 < items[m].1 { m = l }
                if r < items.count && items[r].1 < items[m].1 { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}
