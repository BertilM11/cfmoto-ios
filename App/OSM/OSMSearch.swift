// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.7: búsqueda de lugares sin internet en el mapa de Guatemala que viene con la app
// (pueblos, zonas y colonias, gasolineras, hospitales, centros comerciales, calles…).
// Datos © OpenStreetMap (ODbL).
import Foundation

/// Un lugar encontrado.
struct OSMSearchResult {
    let title: String
    /// Tipo y zona: «Calle · Zona 10, Guatemala».
    let subtitle: String
    let point: GeoPoint
    let kind: Int
}

final class OSMSearch {
    private struct Entry {
        let place: Int
        let name: String
        let folded: [UInt8]
        let tokens: [[UInt8]]
        let area: Int32
        let point: GeoPoint
        let kind: Int
    }

    private struct Area {
        let name: String
        let tokens: [[UInt8]]
        /// Ciudad o pueblo al que pertenece la zona o colonia (-1 si no hay).
        var town: Int32
        let point: GeoPoint
        let kind: Int
    }

    let map: OSMMapData
    private var entries: [Entry] = []
    private var areas: [Area] = []
    /// Lugares del índice (las calles partidas en varios tramos cuentan una vez por zona).
    var count: Int { entries.count }

    init(map: OSMMapData) {
        self.map = map
        build()
    }

    // MARK: - Texto

    private static let ordinals: Set<String> = ["a", "o", "ra", "da", "ta", "va", "na", "ma", "er", "era", "do", "to", "ro", "vo", "no", "mo"]
    private static let stopWords: Set<String> = ["de", "del", "la", "el", "los", "las", "y", "en"]
    private static let synonyms: [String: String] = [
        "av": "avenida", "ave": "avenida", "avda": "avenida", "avenue": "avenida",
        "calz": "calzada", "blvd": "bulevar", "boulevard": "bulevar", "bulevard": "bulevar", "blv": "bulevar",
        "col": "colonia", "carr": "carretera", "cc": "centro", "hosp": "hospital", "gas": "gasolinera",
    ]

    /// Palabras normalizadas: sin acentos ni mayúsculas, «6a» y «6» iguales, «z10» como «zona 10».
    static func tokens(_ text: String) -> [String] {
        let lowered = text.replacingOccurrences(of: "ª", with: "a").replacingOccurrences(of: "º", with: "o")
            .replacingOccurrences(of: "°", with: "o")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "es"))
        var words: [String] = []
        var current = ""
        var digits = false
        func flush() {
            if !current.isEmpty { words.append(current) }
            current = ""
        }
        for ch in lowered {
            if ch.isNumber && ch.isASCII {
                if !digits { flush() }
                digits = true
                current.append(ch)
            } else if ch.isLetter {
                if digits { flush() }
                digits = false
                current.append(ch)
            } else {
                flush()
                digits = false
            }
        }
        flush()
        var out: [String] = []
        for (i, w) in words.enumerated() {
            let afterNumber = i > 0 && words[i - 1].first?.isNumber == true
            if afterNumber && ordinals.contains(w) { continue }
            if w == "z", i + 1 < words.count, words[i + 1].first?.isNumber == true {
                out.append("zona")
                continue
            }
            out.append(synonyms[w] ?? w)
        }
        return out
    }

    private static func bytes(_ tokens: [String]) -> [[UInt8]] {
        tokens.map { Array($0.utf8) }
    }

    private static func isNumber(_ t: [UInt8]) -> Bool {
        guard let f = t.first else { return false }
        return f >= 48 && f <= 57
    }

    private static func hasPrefix(_ t: [UInt8], _ q: [UInt8]) -> Bool {
        guard q.count <= t.count else { return false }
        var i = 0
        while i < q.count {
            if t[i] != q[i] { return false }
            i += 1
        }
        return true
    }

    // MARK: - Índice

    private func build() {
        let n = map.placeCount
        var raw: [(place: Int, name: UInt32, point: GeoPoint, kind: Int)] = []
        raw.reserveCapacity(n)
        for i in 0..<n {
            let p = map.place(i)
            guard p.name != OSMMapData.noName else { continue }
            raw.append((place: i, name: p.name, point: p.point.geo, kind: p.kind))
        }
        // Zonas, colonias, ciudades, pueblos y aldeas: dan el «dónde» de cada resultado.
        var areaIndex: [Int: Int32] = [:]
        for r in raw where r.kind >= 1 && r.kind <= 6 {
            let name = map.name(r.name)
            areaIndex[r.place] = Int32(areas.count)
            areas.append(Area(name: name, tokens: OSMSearch.bytes(OSMSearch.tokens(name)), town: -1, point: r.point, kind: r.kind))
        }
        // Rejilla de 0,05° para buscar la zona más cercana rápido.
        func key(_ g: GeoPoint) -> Int {
            Int(floor(g.lat / 0.05)) * 100_000 + Int(floor(g.lon / 0.05))
        }
        var grid: [Int: [Int32]] = [:]
        for (i, a) in areas.enumerated() {
            grid[key(a.point), default: []].append(Int32(i))
        }
        func nearest(_ g: GeoPoint, kinds: ClosedRange<Int>, within: Double) -> Int32 {
            var best: Int32 = -1
            var bestD = within
            let r0 = Int(floor(g.lat / 0.05))
            let c0 = Int(floor(g.lon / 0.05))
            for dr in -2...2 {
                for dc in -2...2 {
                    guard let list = grid[(r0 + dr) * 100_000 + (c0 + dc)] else { continue }
                    for i in list {
                        let a = areas[Int(i)]
                        guard kinds.contains(a.kind) else { continue }
                        let d = g.distance(to: a.point)
                        if d < bestD {
                            bestD = d
                            best = i
                        }
                    }
                }
            }
            return best
        }
        // La ciudad o el pueblo de cada zona o colonia.
        for i in areas.indices where areas[i].kind >= 4 {
            areas[i].town = nearest(areas[i].point, kinds: 1...3, within: 12_000)
        }

        var seen: [String: Int] = [:]
        entries.reserveCapacity(raw.count / 2)
        for r in raw {
            let isArea = r.kind >= 1 && r.kind <= 6
            let area: Int32
            if isArea {
                area = areaIndex[r.place].map { areas[Int($0)].town } ?? -1
            } else {
                let zone = nearest(r.point, kinds: 4...5, within: 2_500)
                area = zone >= 0 ? zone : nearest(r.point, kinds: 1...6, within: 12_000)
            }
            // Una calle partida en muchos tramos aparece una vez por zona (o por cada 2 km si no hay zona).
            if r.kind == 30 {
                let cell = area >= 0 ? "z\(area)" : "c\(Int(floor(r.point.lat / 0.02)))_\(Int(floor(r.point.lon / 0.02)))"
                let k = "\(r.name)|\(cell)"
                if seen[k] != nil { continue }
                seen[k] = entries.count
            }
            let name = map.name(r.name)
            let tokens = OSMSearch.tokens(name)
            guard !tokens.isEmpty else { continue }
            entries.append(Entry(place: r.place, name: name, folded: Array(tokens.joined(separator: " ").utf8),
                                 tokens: OSMSearch.bytes(tokens), area: area, point: r.point, kind: r.kind))
        }
    }

    // MARK: - Búsqueda

    /// Hasta `limit` lugares que contienen todas las palabras escritas (la última puede estar a
    /// medias), los más parecidos y cercanos primero.
    func search(_ query: String, near: GeoPoint?, limit: Int = 7) -> [OSMSearchResult] {
        var words = OSMSearch.tokens(query)
        let meaningful = words.filter { !OSMSearch.stopWords.contains($0) }
        if !meaningful.isEmpty { words = meaningful }
        guard !words.isEmpty else { return [] }
        let typing = !(query.last.map { $0 == " " } ?? false)
        let q = OSMSearch.bytes(words)
        let joined = Array(words.joined(separator: " ").utf8)

        func matches(_ token: [UInt8], _ word: [UInt8], last: Bool) -> Bool {
            if OSMSearch.isNumber(word) {
                // «1» no debe encontrar «14 Calle», salvo mientras se escribe el número.
                return token == word || (last && typing && OSMSearch.hasPrefix(token, word))
            }
            return OSMSearch.hasPrefix(token, word)
        }

        var scored: [(score: Double, entry: Int)] = []
        for (ei, e) in entries.enumerated() {
            var inName = 0
            var ok = true
            for (wi, w) in q.enumerated() {
                let last = wi == q.count - 1
                if e.tokens.contains(where: { matches($0, w, last: last) }) {
                    inName += 1
                    continue
                }
                // La palabra puede ser de la zona o del pueblo («14 calle zona 10»).
                var found = false
                if e.area >= 0 {
                    let a = areas[Int(e.area)]
                    found = a.tokens.contains(where: { matches($0, w, last: last) })
                    if !found, a.town >= 0 {
                        found = areas[Int(a.town)].tokens.contains(where: { matches($0, w, last: last) })
                    }
                }
                if !found {
                    ok = false
                    break
                }
            }
            guard ok, inName > 0 else { continue }
            var score = Double(inName) * 10
            if e.folded == joined { score += 40 } else if OSMSearch.hasPrefix(e.folded, joined) { score += 18 }
            if inName == q.count && e.tokens.count == q.count { score += 8 }
            switch e.kind {
            case 1: score += 14
            case 2: score += 11
            case 4, 5: score += 9
            case 3: score += 7
            case 6: score += 3
            case 30: score += 0
            default: score += 5
            }
            if let here = near {
                let km = here.distance(to: e.point) / 1000
                score -= log10(km + 1) * 9
            }
            scored.append((score, ei))
        }
        scored.sort { $0.score > $1.score }
        var out: [OSMSearchResult] = []
        var shown: Set<String> = []
        for s in scored {
            let e = entries[s.entry]
            let subtitle = describe(e)
            let key = e.name + "|" + subtitle
            if shown.contains(key) { continue }
            shown.insert(key)
            out.append(OSMSearchResult(title: e.name, subtitle: subtitle, point: e.point, kind: e.kind))
            if out.count >= limit { break }
        }
        return out
    }

    private func describe(_ e: Entry) -> String {
        let what = OSMPlace(point: OSMPoint(e.point), name: 0, kind: e.kind).kindTitle
        guard e.area >= 0 else { return what }
        let a = areas[Int(e.area)]
        var whereText = a.name
        if a.town >= 0, areas[Int(a.town)].name != a.name {
            whereText += ", " + areas[Int(a.town)].name
        }
        return what + " · " + whereText
    }
}
