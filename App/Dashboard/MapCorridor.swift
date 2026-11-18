// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mapa guardado de la ruta, para cuando el iPhone se bloquea.
//
// Apple entrega las instantáneas de MKMapSnapshotter solo con la app en primer plano: si se
// piden en segundo plano, llegan cuando la app vuelve a abrirse (documentación de
// MKMapSnapshotter.start). Por eso, con la app abierta, se fotografía la ruta por delante y,
// con el iPhone bloqueado, se usan esas imágenes.
//
// Aquí está todo lo que no depende de MapKit: qué tramos faltan, cuánto cubre lo guardado,
// qué se conserva al recalcular la ruta y qué imagen usar en cada fotograma. Sin UIKit ni
// MapKit: se prueba en macOS (Tools/DashboardCheck).
import Foundation
import CoreGraphics

enum MapCorridor {
    /// Dónde queda la moto dentro de la imagen (fracción del alto, desde arriba).
    static let puckY = 0.72
    /// Parte de la imagen en la que la moto puede estar para usarla (márgenes de seguridad).
    static let usableX = 0.1...0.9
    static let usableY = 0.3...0.94
    /// 0.6.3: imágenes de la ruta que se piden a la vez (además de la de en vivo). Eran 2.
    static let parallelPrefetch = 3
    /// 0.6.3: tope de imágenes guardadas (eran 400). Con unos 90 KB por imagen, ~70 MB.
    static let maxImages = 800
    /// 0.6.3: memoria máxima para el mapa guardado (eran 64 MB). Nunca más de 1/5 de la que le
    /// queda libre a la app.
    static let budgetCap = 96 << 20
    static let budgetFloor = 16 << 20

    /// Memoria para el mapa guardado según la que le queda libre a la app.
    static func budget(available: Int) -> Int {
        guard available > 0 else { return 48 << 20 }
        return max(budgetFloor, min(budgetCap, available / 5))
    }
}

/// 0.6.3: cuánta ruta tiene mapa guardado, dicho igual en el iPhone y en la moto.
struct MapCoverageState: Equatable {
    enum Kind: String {
        case none, saving, complete, partial
    }
    var kind: Kind
    /// Metros seguidos con mapa guardado desde la posición actual.
    var available: Double
    /// Metros de ruta que quedan.
    var remaining: Double

    static let none = MapCoverageState(kind: .none, available: 0, remaining: 0)

    /// `horizon`: hasta dónde se intenta guardar (lo limita la memoria). `cached` y `capacity`:
    /// imágenes guardadas y máximo que cabe.
    static func make(routeActive: Bool, remaining: Double, continuous: Double, horizon: Double,
                     cached: Int, capacity: Int) -> MapCoverageState {
        guard routeActive else { return .none }
        let left = max(0, remaining)
        let have = max(0, min(continuous, left))
        if have >= left - 30 { return MapCoverageState(kind: .complete, available: left, remaining: left) }
        // No cabe toda la ruta: lo guardado llega hasta donde da la memoria.
        let limited = horizon + 1 < left || (capacity > 0 && cached >= capacity)
        return MapCoverageState(kind: limited ? .partial : .saving, available: have, remaining: left)
    }

    /// Texto para el iPhone.
    var text: String {
        switch kind {
        case .none: return ""
        case .complete:
            return remaining < 100 ? "Ruta completa guardada" : "Ruta completa guardada: \(HUDFormat.distance(remaining))"
        case .saving: return "Guardando el mapa: \(HUDFormat.distance(available)) de \(HUDFormat.distance(remaining))"
        case .partial: return "Mapa parcial: \(HUDFormat.distance(available)) de \(HUDFormat.distance(remaining)) (límite de memoria)"
        }
    }

    /// Qué hacer, en una línea, para el iPhone.
    var advice: String {
        switch kind {
        case .none: return ""
        case .complete: return "Ya puedes bloquear el iPhone: la moto tiene el mapa de toda la ruta."
        case .saving: return "Espera a «Ruta completa guardada» antes de bloquear, o usa la pantalla negra."
        case .partial: return "Con el iPhone bloqueado, después de \(HUDFormat.distance(available)) la moto mostrará el mapa simple. La pantalla negra mantiene el mapa en vivo."
        }
    }

    /// Aviso en la moto: solo con el mapa guardado en uso (iPhone bloqueado), cuando no está la
    /// ruta completa y quedan menos de 2 km de mapa. Sin mapa guardado ya sale MAPA SIMPLE.
    func tftTag(storedMapInUse: Bool) -> String? {
        guard storedMapInUse, kind == .saving || kind == .partial, available >= 50, available < 2000 else { return nil }
        return "MAPA GUARDADO: " + HUDFormat.distance(available).uppercased()
    }
}

extension GeoPoint {
    /// Rumbo hacia otro punto, en grados desde el norte (0…360).
    func bearing(to o: GeoPoint) -> Double {
        let dy = (o.lat - lat) * 110_574.0
        let dx = (o.lon - lon) * 111_320.0 * cos(lat * .pi / 180)
        var b = atan2(dx, dy) * 180 / .pi
        if b < 0 { b += 360 }
        return b
    }
}

/// Diferencia entre dos rumbos, de 0 a 180 grados.
func headingGap(_ a: Double, _ b: Double) -> Double {
    var d = abs(a - b).truncatingRemainder(dividingBy: 360)
    if d > 180 { d = 360 - d }
    return d
}

/// Ruta en coordenadas con sus distancias acumuladas.
struct RoutePath {
    let points: [GeoPoint]
    let cumulative: [Double]

    init(points input: [GeoPoint]) {
        var pts: [GeoPoint] = []
        pts.reserveCapacity(input.count)
        for p in input where pts.last.map({ $0.distance(to: p) > 0.5 }) ?? true {
            pts.append(p)
        }
        var cum: [Double] = []
        cum.reserveCapacity(pts.count)
        var total = 0.0
        for i in pts.indices {
            if i > 0 { total += pts[i - 1].distance(to: pts[i]) }
            cum.append(total)
        }
        points = pts
        cumulative = cum
    }

    var length: Double { cumulative.last ?? 0 }
    var isEmpty: Bool { points.count < 2 }

    /// Tramo que contiene la distancia `d` (índice del punto inicial).
    private func segment(at d: Double) -> Int {
        var lo = 0
        var hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= d { lo = mid } else { hi = mid }
        }
        return lo
    }

    func point(at d: Double) -> GeoPoint {
        guard let first = points.first else { return GeoPoint(lat: 0, lon: 0) }
        guard points.count >= 2 else { return first }
        let x = max(0, min(length, d))
        let i = segment(at: x)
        let a = points[i]
        let b = points[i + 1]
        let span = cumulative[i + 1] - cumulative[i]
        let t = span > 0 ? (x - cumulative[i]) / span : 0
        return GeoPoint(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t)
    }

    /// Rumbo de la ruta en `d` (grados desde el norte), medido sobre `span` metros.
    func bearing(at d: Double, span: Double = 40) -> Double {
        let a = point(at: d - span / 2)
        let b = point(at: d + span / 2)
        guard a.distance(to: b) > 1 else { return 0 }
        return a.bearing(to: b)
    }

    /// Punto de la ruta más cercano a `g`: metros a lo largo de la ruta y separación lateral.
    func locate(_ g: GeoPoint) -> (along: Double, offset: Double) {
        guard points.count >= 2 else {
            return (0, points.first.map { $0.distance(to: g) } ?? .greatestFiniteMagnitude)
        }
        let mLat = 110_574.0
        let mLon = 111_320.0 * cos(g.lat * .pi / 180)
        var bestAlong = 0.0
        var bestOffset = Double.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ax = (a.lon - g.lon) * mLon
            let ay = (a.lat - g.lat) * mLat
            let dx = (b.lon - g.lon) * mLon - ax
            let dy = (b.lat - g.lat) * mLat - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let dist = hypot(ax + dx * t, ay + dy * t)
            if dist < bestOffset {
                bestOffset = dist
                bestAlong = cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t
            }
        }
        return (bestAlong, bestOffset)
    }

    /// Distancias donde la ruta gira (cambio de rumbo de al menos `minAngle` grados). Ahí se
    /// guarda una imagen más, ya orientada hacia la calle nueva.
    func turns(minAngle: Double = 35, step: Double = 20) -> [Double] {
        guard length > 80 else { return [] }
        var out: [Double] = []
        var lastTurn = -Double.greatestFiniteMagnitude
        var d = 30.0
        while d < length - 30 {
            let before = bearing(at: d - 25, span: 30)
            let after = bearing(at: d + 25, span: 30)
            if headingGap(before, after) >= minAngle && d - lastTurn > 80 {
                out.append(d)
                lastTurn = d
            }
            d += step
        }
        return out
    }
}

/// Una imagen guardada a lo largo de la ruta.
struct CorridorEntry {
    let base: MapBase
    /// Metros de ruta a los que corresponde: ahí estaba la moto al pedirla.
    var anchor: Double
    /// Metros que el centro de la imagen va por delante de la moto.
    let ahead: Double

    var bytes: Int { base.byteCount }
}

/// Una imagen que falta guardar.
struct CorridorRequest: Equatable {
    var anchor: Double
    var here: GeoPoint
    var heading: Double
    var night: Bool
}

enum CorridorPlanner {
    /// Separación entre imágenes guardadas. La moto entra por abajo de la parte útil y sale
    /// por arriba; con esta separación cada tramo queda en al menos dos imágenes.
    static func step(visible: Double) -> Double { max(60, visible * 0.42) }

    /// La separación se mantiene mientras la calibración de Apple no cambie de verdad (más
    /// de un 15 %). Antes se recalculaba con cada imagen: la rejilla se movía un poco, lo ya
    /// guardado dejaba de coincidir y se volvía a pedir cerca de la moto.
    static func stableStep(current: Double, visible: Double) -> Double {
        let fresh = step(visible: visible)
        guard current > 0 else { return fresh }
        return abs(fresh - current) / current > 0.15 ? fresh : current
    }

    /// Cuántas imágenes caben en la memoria permitida.
    static func capacity(budgetBytes: Int, averageBytes: Int, maxImages: Int) -> Int {
        guard averageBytes > 0 else { return maxImages }
        return max(0, min(maxImages, budgetBytes / averageBytes))
    }

    /// Hasta cuántos metros por delante guardar: toda la ruta que queda, si cabe.
    static func horizon(remaining: Double, capacity: Int, step: Double) -> Double {
        max(0, min(remaining + step, Double(capacity) * step))
    }

    /// Dónde debe haber imagen (metros de ruta), de la más cercana a la más lejana: una cada
    /// `step` metros y otra justo después de cada giro.
    static func anchors(route: RoutePath, from progress: Double, to end: Double, step: Double, turns: [Double]) -> [Double] {
        guard !route.isEmpty, end > progress, step > 0 else { return [] }
        var all: [(at: Double, turn: Bool)] = []
        // Rejilla fija desde el inicio de la ruta: no se mueve con la moto. Antes empezaba en
        // la posición actual, así que al avanzar unos metros nada de lo guardado coincidía y
        // se volvía a pedir el tramo más cercano una y otra vez (en la prueba del simulador:
        // 26 imágenes para menos de 1 km). La primera es la que todavía cubre la posición.
        var d = (max(0, progress) / step).rounded(.down) * step
        let last = min(end, route.length)
        while d < last {
            all.append((d, false))
            d += step
        }
        for t in turns where t + 15 > progress && t + 15 < last {
            all.append((t + 15, true))
        }
        all.sort { $0.at < $1.at }
        var out: [(at: Double, turn: Bool)] = []
        for a in all {
            if let previous = out.last, a.at - previous.at < 12 {
                // Casi en el mismo sitio: se queda la de después del giro.
                if a.turn && !previous.turn { out[out.count - 1] = a }
                continue
            }
            out.append(a)
        }
        return out.map { $0.at }
    }

    /// Rumbo de la imagen de un ancla: el de la ruta un poco por delante de la moto.
    static func heading(route: RoutePath, at anchor: Double, northUp: Bool) -> Double {
        northUp ? 0 : route.bearing(at: anchor + 40, span: 60)
    }

    /// Las imágenes que faltan (ni guardadas ni pedidas), de la más cercana a la más lejana.
    static func missing(
        anchors: [Double], route: RoutePath, existing: [CorridorEntry], inFlight: [Double],
        night: (Double) -> Bool, styleKey: (Bool) -> String, northUp: Bool, step: Double, limit: Int
    ) -> [CorridorRequest] {
        guard limit > 0 else { return [] }
        let sorted = existing.sorted { $0.anchor < $1.anchor }
        var out: [CorridorRequest] = []
        for (i, a) in anchors.enumerated() {
            if out.count >= limit { break }
            if inFlight.contains(where: { abs($0 - a) < step * 0.25 }) { continue }
            let n = night(a)
            let key = styleKey(n)
            let h = heading(route: route, at: a, northUp: northUp)
            let saved = existing.contains { e in
                abs(e.anchor - a) < step * 0.25 && e.base.styleKey == key && headingGap(e.base.heading, h) < 20
            }
            if saved { continue }
            // Lo que le toca a esta imagen (hasta la siguiente) ya lo cubren otras, por ejemplo
            // las conservadas al recalcular, que no caen en la rejilla de la ruta nueva: no se
            // pide otra vez lo mismo.
            let until = i + 1 < anchors.count ? anchors[i + 1] : a + step
            if CorridorCoverage.covers(sorted, route: route, from: a, to: until, northUp: northUp, style: key) { continue }
            out.append(CorridorRequest(anchor: a, here: route.point(at: a), heading: h, night: n))
        }
        return out
    }

    /// Al cambiar de ruta (recálculo o ruta nueva) se conservan las imágenes que siguen
    /// sirviendo: la moto pasa por ese punto y en la misma dirección.
    static func retain(_ entries: [CorridorEntry], on route: RoutePath, northUp: Bool, tolerance: Double = 60) -> [CorridorEntry] {
        guard !route.isEmpty else { return [] }
        var out: [CorridorEntry] = []
        for var e in entries {
            let here = e.base.center.moved(-e.ahead, bearing: e.base.heading)
            let place = route.locate(here)
            guard place.offset < tolerance else { continue }
            if !northUp && headingGap(heading(route: route, at: place.along, northUp: false), e.base.heading) > 30 {
                continue
            }
            e.anchor = place.along
            out.append(e)
        }
        return out.sorted { $0.anchor < $1.anchor }
    }

    /// Si no caben todas, se sueltan las más lejanas (se volverán a pedir al acercarse).
    static func trim(_ entries: [CorridorEntry], progress: Double, capacity: Int) -> [CorridorEntry] {
        let kept = entries.filter { $0.anchor >= progress - 400 }
        guard kept.count > capacity else { return kept }
        return Array(kept.sorted { abs($0.anchor - progress) < abs($1.anchor - progress) }.prefix(capacity))
            .sorted { $0.anchor < $1.anchor }
    }
}

/// Cuánto de la ruta tiene imagen guardada utilizable.
enum CorridorCoverage {
    struct Result: Equatable {
        /// Metros seguidos con imagen, desde la posición actual.
        var continuous: Double
        /// Metros con imagen en total, hasta el final de lo revisado.
        var covered: Double
        /// Metros revisados (hasta el final de la ruta o del límite).
        var checked: Double
        /// Tramos sin imagen.
        var gaps: Int
    }

    /// ¿Hay alguna imagen en la que se vería bien la moto en `d`?
    static func usable(_ entries: [CorridorEntry], route: RoutePath, at d: Double, northUp: Bool, style: String?) -> Bool {
        let p = route.point(at: d)
        let h = route.bearing(at: d, span: 30)
        for e in entries where abs(e.anchor - d) < 1500 {
            if let s = style, e.base.styleKey != s { continue }
            if !northUp && headingGap(e.base.heading, h) >= 55 { continue }
            guard let q = e.base.project(p) else { continue }
            if MapCorridor.usableX.contains(Double(q.x)) && MapCorridor.usableY.contains(Double(q.y)) {
                return true
            }
        }
        return false
    }

    /// ¿Todo el tramo de `from` a `to` tiene ya imagen del estilo pedido? `sorted`: ordenadas
    /// por ancla.
    static func covers(_ sorted: [CorridorEntry], route: RoutePath, from: Double, to: Double,
                       northUp: Bool, style: String, sample: Double = 25) -> Bool {
        guard to > from, !sorted.isEmpty else { return false }
        // Solo las imágenes cercanas al tramo (búsqueda binaria del primer ancla útil).
        var lo = 0
        var hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].anchor < from - 1500 { lo = mid + 1 } else { hi = mid }
        }
        var near: [CorridorEntry] = []
        var i = lo
        while i < sorted.count && sorted[i].anchor <= to + 1500 {
            if sorted[i].base.styleKey == style { near.append(sorted[i]) }
            i += 1
        }
        guard !near.isEmpty else { return false }
        var d = from
        while d < to {
            if !usable(near, route: route, at: d, northUp: northUp, style: style) { return false }
            d += sample
        }
        return true
    }

    static func scan(route: RoutePath, from progress: Double, to end: Double, entries: [CorridorEntry],
                     northUp: Bool, style: String? = nil, sample: Double = 25) -> Result {
        guard !route.isEmpty, end > progress else { return Result(continuous: 0, covered: 0, checked: 0, gaps: 0) }
        let sorted = entries.sorted { $0.anchor < $1.anchor }
        let last = min(end, route.length)
        // 0.6.3: la posición y puntos fijos de la ruta (cada `sample` metros desde el inicio).
        // Antes los puntos se movían con la moto: un hueco de pocos metros entre dos imágenes
        // aparecía o no según el instante y los km guardados saltaban (en el simulador, 4,0 →
        // 1,8 → 3,9 km en 20 s sin imágenes nuevas).
        var points: [Double] = [progress]
        var g = ((progress / sample).rounded(.down) + 1) * sample
        while g <= last {
            points.append(g)
            g += sample
        }
        var lower = 0
        var ok: [Bool] = []
        ok.reserveCapacity(points.count)
        for d in points {
            // Solo las imágenes cercanas a este punto de la ruta.
            while lower < sorted.count && sorted[lower].anchor < d - 1500 { lower += 1 }
            var near: [CorridorEntry] = []
            var i = lower
            while i < sorted.count && sorted[i].anchor <= d + 1500 {
                near.append(sorted[i])
                i += 1
            }
            ok.append(usable(near, route: route, at: d, northUp: northUp, style: style))
        }
        var continuous = 0.0
        var stillContinuous = true
        var covered = 0.0
        var gaps = 0
        var inGap = false
        for j in points.indices {
            let next = j + 1 < points.count ? points[j + 1] : min(last, points[j] + sample)
            let length = max(0, next - points[j])
            // Un solo punto sin imagen entre dos con imagen (hueco de menos de dos puntos) no corta
            // lo seguido: lo cubre la imagen vecina (el dibujo acepta también imágenes con la moto
            // cerca del borde).
            let good = ok[j] || (j > 0 && j + 1 < points.count && ok[j - 1] && ok[j + 1])
            if good {
                covered += length
                if stillContinuous { continuous = next - progress }
                inGap = false
            } else {
                stillContinuous = false
                if !inGap { gaps += 1 }
                inGap = true
            }
        }
        let checked = last - progress
        return Result(continuous: min(continuous, checked), covered: min(covered, checked), checked: checked, gaps: gaps)
    }
}

/// De dónde sale el mapa del fotograma actual (para el diagnóstico).
enum MapSource: String {
    case live = "en vivo"
    case cached = "guardada"
    case cachedOtherStyle = "guardada con el otro tema"
    case cachedLoose = "guardada (orientación aproximada)"
    case liveOld = "última en vivo (vieja)"
    case none = "ninguna: mapa simple"
}

/// Qué imagen usar en cada fotograma.
enum MapChooser {
    static func choose(live: MapBase?, entries: [CorridorEntry], pose: MapPose, wantedStyle: String,
                       now: TimeInterval, preview: Bool, northUp: Bool) -> (base: MapBase?, source: MapSource) {
        func spot(_ b: MapBase) -> CGPoint? { b.project(pose.here) }
        func gap(_ b: MapBase) -> Double {
            (northUp || pose.heading < 0) ? 0 : headingGap(b.heading, pose.heading)
        }
        // Antes de empezar: la vista general en vivo.
        if preview, let l = live { return (l, .live) }
        // En vivo y reciente, con la moto bien dentro.
        if let l = live, now - l.created < 30, let q = spot(l), q.x > 0.06, q.x < 0.94, q.y > 0.22, q.y < 0.96 {
            return (l, .live)
        }
        let near = entries.filter { e in pose.progress.map { abs(e.anchor - $0) < 3000 } ?? true }
        // 1) Guardadas, con la moto en la parte útil y orientación parecida. El tema correcto
        //    gana siempre; el otro tema solo si no hay ninguna del correcto.
        var best: (MapBase, Double)?
        for e in near {
            guard let q = spot(e.base), MapCorridor.usableX.contains(Double(q.x)), MapCorridor.usableY.contains(Double(q.y)) else { continue }
            let g = gap(e.base)
            guard g < 55 else { continue }
            let score = abs(Double(q.y) - MapCorridor.puckY) + g / 90 + (e.base.styleKey == wantedStyle ? 0 : 5)
            if best == nil || score < best!.1 { best = (e.base, score) }
        }
        if let b = best {
            return (b.0, b.0.styleKey == wantedStyle ? .cached : .cachedOtherStyle)
        }
        // 2) Último recurso antes del mapa simple: cualquier imagen que contenga la posición,
        //    aunque esté girada o sea vieja (las calles siguen en su sitio).
        var loose: (MapBase, Double, MapSource)?
        var candidates = near.map { ($0.base, MapSource.cachedLoose) }
        if let l = live { candidates.append((l, .liveOld)) }
        for (b, source) in candidates {
            guard let q = spot(b), q.x > 0.03, q.x < 0.97, q.y > 0.08, q.y < 0.985 else { continue }
            let g = gap(b)
            guard g < 100 else { continue }
            let score = abs(Double(q.y) - MapCorridor.puckY) + g / 60 + (b.styleKey == wantedStyle ? 0 : 5)
            if loose == nil || score < loose!.1 { loose = (b, score, source) }
        }
        if let l = loose { return (l.0, l.2) }
        return (nil, .none)
    }
}
