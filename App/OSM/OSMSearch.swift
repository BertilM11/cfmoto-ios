// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.7: búsqueda de lugares sin internet en el mapa de Guatemala que viene con la app
// (ciudades y pueblos, zonas y colonias, gasolineras, hospitales, centros comerciales, calles…).
// Cada resultado dice dónde está (zona, municipio o departamento, de los límites de
// OpenStreetMap). Datos © colaboradores de OpenStreetMap (ODbL).
import Foundation

/// Un lugar encontrado.
struct OSMSearchResult {
    let title: String
    /// Tipo y lugar: «Calle · Zona 10, Ciudad de Guatemala».
    let subtitle: String
    let point: GeoPoint
    let kind: Int
}

final class OSMSearch {
    private struct Entry {
        /// Nombre que se muestra (el principal, aunque se haya encontrado por otro nombre).
        let title: UInt32
        /// El otro nombre con el que se encontró (alt_name…), o `noName`.
        let alias: UInt32
        let tokens: [[UInt8]]
        let folded: [UInt8]
        let zone: Int32
        let admin: Int32
        let point: GeoPoint
        let kind: Int
        /// El lugar principal (para no repetirlo con cada uno de sus nombres).
        let main: Int32
    }

    private struct Zone {
        let name: UInt32
        let tokens: [[UInt8]]
        let point: GeoPoint
        let admin: Int32
    }

    private struct Admin {
        let name: UInt32
        let tokens: [[UInt8]]
        let parent: Int32
        let kind: Int
    }

    let map: OSMMapData
    private var entries: [Entry] = []
    private var zones: [Zone] = []
    private var admins: [Int32: Admin] = [:]
    private var tokenCache: [UInt32: [[UInt8]]] = [:]
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
        "col": "colonia", "carr": "carretera", "hosp": "hospital",
    ]
    /// Palabras que nombran un tipo de lugar: «gasolinera» encuentra las gasolineras aunque se
    /// llamen Texaco o Puma.
    private static let categories: [String: [Int]] = [
        "gasolinera": [10], "gasolineras": [10], "gasolina": [10], "combustible": [10],
        "hospital": [11], "hospitales": [11], "clinica": [11], "clinicas": [11], "sanatorio": [11],
        "policia": [12], "universidad": [13], "escuela": [14], "colegio": [14], "instituto": [14], "mercado": [15],
        "banco": [16], "bancos": [16], "cajero": [16], "restaurante": [17], "restaurantes": [17], "comida": [17],
        "cafe": [17], "cafeteria": [17], "farmacia": [18], "farmacias": [18], "parqueo": [19], "parqueadero": [19],
        "estacionamiento": [19], "iglesia": [20], "templo": [20], "mall": [21], "comercial": [21],
        "supermercado": [22], "super": [22], "motos": [23], "moto": [23], "taller": [24], "mecanico": [24],
        "ferreteria": [25], "hotel": [26], "hoteles": [26], "hostal": [26], "museo": [27], "mirador": [27],
        "terminal": [28], "buses": [28], "estadio": [29], "municipalidad": [31], "aeropuerto": [32],
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

    private func tokens(of name: UInt32) -> [[UInt8]] {
        if let t = tokenCache[name] { return t }
        let t = OSMSearch.bytes(OSMSearch.tokens(map.name(name)))
        tokenCache[name] = t
        return t
    }

    private static func weight(_ kind: Int) -> Double {
        switch kind {
        case 1: return 14
        case 2: return 11
        case 3: return 7
        case 4, 5: return 9
        case 6: return 3
        case 10: return 6
        case 11: return 7
        case 12: return 5
        case 13: return 6
        case 15: return 5
        case 18: return 3
        case 19: return 0
        case 21: return 8
        case 22: return 6
        case 23: return 4
        case 24, 25: return 3
        case 26: return 4
        case 27: return 5
        case 28, 29: return 6
        case 30, 31: return 5
        case 32: return 12
        case 33: return 2
        case 34: return 6
        default: return 2
        }
    }

    // MARK: - Índice

    private func build() {
        let n = map.placeCount
        var raw: [(index: Int32, place: OSMPlace, point: GeoPoint)] = []
        raw.reserveCapacity(n)
        for i in 0..<n {
            let p = map.place(i)
            guard p.name != OSMMapData.noName else { continue }
            raw.append((index: Int32(i), place: p, point: p.point.geo))
        }
        // Departamentos y municipios (formato 2): el «dónde» de cada lugar.
        for r in raw where r.place.kind == 40 || r.place.kind == 41 {
            admins[r.index] = Admin(name: r.place.name, tokens: tokens(of: r.place.name), parent: Int32(r.place.admin), kind: r.place.kind)
        }
        // Zonas y colonias, en una rejilla de 0,05° para buscar la más cercana rápido.
        var grid: [Int: [Int32]] = [:]
        func key(_ row: Int, _ col: Int) -> Int { row * 100_000 + col }
        for r in raw where (r.place.kind == 4 || r.place.kind == 5) && !r.place.alias {
            grid[key(Int(floor(r.point.lat / 0.05)), Int(floor(r.point.lon / 0.05))), default: []].append(Int32(zones.count))
            zones.append(Zone(name: r.place.name, tokens: tokens(of: r.place.name), point: r.point, admin: Int32(r.place.admin)))
        }
        func nearestZone(_ g: GeoPoint, admin: Int32) -> Int32 {
            var best: Int32 = -1
            var bestD = 2_500.0
            let r0 = Int(floor(g.lat / 0.05))
            let c0 = Int(floor(g.lon / 0.05))
            for dr in -1...1 {
                for dc in -1...1 {
                    guard let list = grid[key(r0 + dr, c0 + dc)] else { continue }
                    for z in list {
                        let zone = zones[Int(z)]
                        // Una zona de otro municipio no sirve («Zona 10» de Mixco no es la de la capital).
                        if admin >= 0 && zone.admin >= 0 && zone.admin != admin { continue }
                        let d = g.distance(to: zone.point)
                        if d < bestD {
                            bestD = d
                            best = z
                        }
                    }
                }
            }
            return best
        }

        var seen = Set<String>()
        var mainIndex: Int32 = -1
        var mainName = OSMMapData.noName
        entries.reserveCapacity(raw.count * 3 / 4)
        for r in raw {
            let p = r.place
            if p.kind == 40 || p.kind == 41 { continue }
            if !p.alias {
                mainIndex = r.index
                mainName = p.name
            }
            let zone: Int32 = (1...5).contains(p.kind) ? -1 : nearestZone(r.point, admin: Int32(p.admin))
            // Una calle partida en muchos tramos aparece una vez por zona (o cada 2 km si no hay).
            if p.kind == 30 {
                let cell = zone >= 0 ? "z\(zone)" : "m\(p.admin)_\(Int(floor(r.point.lat / 0.02)))_\(Int(floor(r.point.lon / 0.02)))"
                guard seen.insert("\(p.name)|\(cell)").inserted else { continue }
            }
            let t = tokens(of: p.name)
            guard !t.isEmpty else { continue }
            let isAlias = p.alias && mainIndex >= 0
            let folded = Array(t.map { String(decoding: $0, as: UTF8.self) }.joined(separator: " ").utf8)
            entries.append(Entry(title: isAlias ? mainName : p.name, alias: isAlias ? p.name : OSMMapData.noName,
                                 tokens: t, folded: folded, zone: zone, admin: Int32(p.admin), point: r.point, kind: p.kind,
                                 main: isAlias ? mainIndex : r.index))
        }
    }

    // MARK: - Búsqueda

    /// Hasta `limit` lugares que contienen todas las palabras escritas (la última puede estar a
    /// medias), los más parecidos y cercanos primero.
    func search(_ query: String, near: GeoPoint?, limit: Int = 7) -> [OSMSearchResult] {
        let all = OSMSearch.tokens(query)
        var words = all.filter { !OSMSearch.stopWords.contains($0) }
        if words.isEmpty { words = all }
        guard !words.isEmpty else { return [] }
        let typing = !(query.last.map { $0 == " " } ?? false)
        let q = OSMSearch.bytes(words)
        let joined = Array(words.joined(separator: " ").utf8)
        let joinedAll = Array(all.joined(separator: " ").utf8)
        // Por cada palabra, una sola vez: qué tipos de lugar nombra (la última, también a medio
        // escribir) y qué zonas, municipios y departamentos la contienen.
        var kindTable = [Bool](repeating: false, count: words.count * 128)
        var zoneHits: [Set<Int32>] = []
        var adminHits: [Set<Int32>] = []
        for (wi, w) in words.enumerated() {
            var kinds = OSMSearch.categories[w] ?? []
            if wi == words.count - 1 && typing && w.count >= 4 {
                for (c, ks) in OSMSearch.categories where c.hasPrefix(w) { kinds += ks }
            }
            for k in kinds where k >= 0 && k < 128 { kindTable[wi * 128 + k] = true }
            let wb = q[wi]
            let prefixOK = !OSMSearch.isNumber(wb) || (wi == words.count - 1 && typing)
            func has(_ tokens: [[UInt8]]) -> Bool {
                tokens.contains { $0 == wb || (prefixOK && OSMSearch.hasPrefix($0, wb)) }
            }
            var zs = Set<Int32>()
            for (i, z) in zones.enumerated() where has(z.tokens) { zs.insert(Int32(i)) }
            var ads = Set<Int32>()
            for (i, a) in admins where has(a.tokens) { ads.insert(i) }
            zoneHits.append(zs)
            adminHits.append(ads)
        }

        var scored: [(score: Double, entry: Int)] = []
        for ei in entries.indices {
            let e = entries[ei]
            var text = 0.0
            var inName = 0
            var ok = true
            var onlyKind = true
            for (wi, w) in q.enumerated() {
                let last = wi == q.count - 1
                let prefixOK = !OSMSearch.isNumber(w) || (last && typing)
                // La palabra es el tipo de lugar: cuenta como tipo aunque el nombre también la diga,
                // así manda la cercanía y no los lugares que se llaman igual.
                if e.kind >= 0 && e.kind < 128 && kindTable[wi * 128 + e.kind] {
                    text += 10
                    inName += 1
                    continue
                }
                onlyKind = false
                if e.tokens.contains(w) {
                    text += 12
                    inName += 1
                    continue
                }
                if prefixOK && e.tokens.contains(where: { OSMSearch.hasPrefix($0, w) }) {
                    text += 8
                    inName += 1
                    continue
                }
                // La palabra puede ser de la zona, el municipio o el departamento.
                if (e.zone >= 0 && zoneHits[wi].contains(e.zone)) || adminHits[wi].contains(e.admin)
                    || (admins[e.admin].map { adminHits[wi].contains($0.parent) } ?? false) {
                    text += 3
                    continue
                }
                ok = false
                break
            }
            guard ok, inName > 0 else { continue }
            if !onlyKind {
                if e.folded == joined || e.folded == joinedAll {
                    text += 14
                } else if OSMSearch.hasPrefix(e.folded, joinedAll) || OSMSearch.hasPrefix(e.folded, joined) {
                    text += 6
                }
                if e.tokens.allSatisfy({ t in q.contains { $0 == t || OSMSearch.hasPrefix(t, $0) } }) { text += 8 }
            }
            var score = text + OSMSearch.weight(e.kind)
            if let here = near {
                score -= log10(here.distance(to: e.point) / 1000 + 1) * 12
            }
            scored.append((score, ei))
        }
        scored.sort { $0.score > $1.score }
        var out: [OSMSearchResult] = []
        var shownMain = Set<Int32>()
        var shownText = Set<String>()
        for s in scored {
            let e = entries[s.entry]
            if shownMain.contains(e.main) { continue }
            let title = map.name(e.title)
            let place = describe(e, title: title)
            let key = title + "|" + place
            if shownText.contains(key) { continue }
            shownMain.insert(e.main)
            shownText.insert(key)
            var subtitle = place
            if e.alias != OSMMapData.noName { subtitle += " · «" + map.name(e.alias) + "»" }
            out.append(OSMSearchResult(title: title, subtitle: subtitle, point: e.point, kind: e.kind))
            if out.count >= limit { break }
        }
        return out
    }

    private static func departmentName(_ n: String) -> String {
        for prefix in ["Departamento de ", "Departamento del "] where n.hasPrefix(prefix) {
            return String(n.dropFirst(prefix.count))
        }
        return n
    }

    /// Tipo y dónde: zona y municipio para calles y lugares; municipio y departamento para
    /// pueblos; municipio para zonas y colonias.
    private func describe(_ e: Entry, title: String) -> String {
        let what = OSMPlace(point: OSMPoint(e.point), name: 0, kind: e.kind).kindTitle
        var muni: Admin?
        var dept: Admin?
        if let a = admins[e.admin] {
            if a.kind == 40 {
                muni = a
                dept = admins[a.parent]
            } else {
                dept = a
            }
        }
        let m = muni.map { map.name($0.name) }
        let d = dept.map { OSMSearch.departmentName(map.name($0.name)) }
        var parts: [String?]
        switch e.kind {
        case 4, 5, 6: parts = [m ?? d]
        case 1, 2, 3: parts = [m, d]
        default: parts = e.zone >= 0 ? [map.name(zones[Int(e.zone)].name), m] : [m, d]
        }
        var list: [String] = []
        for p in parts {
            if let p = p, !p.isEmpty, p != title, !list.contains(p) { list.append(p) }
        }
        return list.isEmpty ? what : what + " · " + list.joined(separator: ", ")
    }
}
