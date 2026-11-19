// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// 0.7.2: entiende lo que se pega en el buscador cuando no es un nombre: coordenadas en
/// cualquier forma común y enlaces de Google Maps, Apple Maps, Waze u OpenStreetMap.
/// Solo lee el texto: no consulta ningún servicio (los enlaces cortos se abren aparte).
enum PlaceInput {
    enum Parsed: Equatable {
        /// Coordenadas listas (y un nombre, si el enlace lo traía).
        case coordinate(lat: Double, lon: Double, name: String?)
        /// Enlace corto (maps.app.goo.gl…) que hay que abrir para ver a dónde lleva.
        case shortLink(URL)
        /// Un enlace de mapas sin coordenadas legibles.
        case unreadableLink
    }

    /// Devuelve nil si el texto parece un nombre normal para buscar.
    static func parse(_ raw: String) -> Parsed? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1) Un enlace dentro del texto (Google Maps comparte «Nombre\nhttps://…»).
        if let url = firstURL(in: text) {
            if let hit = coordinates(inURL: url) {
                return .coordinate(lat: hit.lat, lon: hit.lon, name: hit.name ?? nameBeforeLink(text))
            }
            if isShortLink(url) {
                return .shortLink(url)
            }
            if isMapLink(url) {
                return .unreadableLink
            }
        }
        // 2) geo:14.6,-90.5
        if text.lowercased().hasPrefix("geo:") {
            let body = String(text.dropFirst(4)).components(separatedBy: CharacterSet(charactersIn: "?;"))[0]
            if let p = pair(body) { return .coordinate(lat: p.lat, lon: p.lon, name: nil) }
        }
        // 3) Grados, minutos y segundos: 14°38'05.6"N 90°30'24.8"W
        if let p = dms(text) {
            return .coordinate(lat: p.lat, lon: p.lon, name: nil)
        }
        // 4) Dos números: «14.6349, -90.5069», «14.6349 -90.5069».
        if let p = pair(text) {
            return .coordinate(lat: p.lat, lon: p.lon, name: nil)
        }
        return nil
    }

    // MARK: - Enlaces

    static func firstURL(in text: String) -> URL? {
        for word in text.components(separatedBy: .whitespacesAndNewlines) {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "<>()\"'.,;"))
            let lower = w.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://"),
               let url = URL(string: w) ?? URL(string: w.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
                return url
            }
        }
        return nil
    }

    static func isShortLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if host == "maps.app.goo.gl" || host == "goo.gl" || host == "g.co" { return true }
        if host == "waze.com" || host.hasSuffix(".waze.com") { return url.path.hasPrefix("/ul/h") }
        return false
    }

    static func isMapLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        return host.contains("google.") && (path.hasPrefix("/maps") || host.hasPrefix("maps."))
            || host == "maps.apple.com" || host.hasSuffix("waze.com")
            || host.hasSuffix("openstreetmap.org") || isShortLink(url)
    }

    /// Lee las coordenadas de un enlace de mapas. En Google, `!3d…!4d…` es el lugar marcado y
    /// `@lat,lon` solo el centro de la vista, así que se prefiere el primero.
    static func coordinates(inURL url: URL) -> (lat: Double, lon: Double, name: String?)? {
        let s = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        func item(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        let placeName = googlePlaceName(url)

        if let m = firstMatch(#"!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)"#, in: s),
           let p = valid(m[0], m[1]) {
            return (p.lat, p.lon, placeName)
        }
        // Parámetros con «lat,lon»: Google (q, query, destination, center, daddr),
        // Apple (ll, q, daddr, sll) y Waze (ll).
        for key in ["destination", "daddr", "query", "q", "ll", "center", "sll", "coordinate"] {
            if let v = item(key), let p = pair(v) {
                let label = key == "ll" ? item("q").flatMap { pair($0) == nil ? $0 : nil } : nil
                return (p.lat, p.lon, label ?? placeName)
            }
        }
        // OpenStreetMap: ?mlat=..&mlon=..  o  #map=17/14.6/-90.5
        if let la = item("mlat").flatMap(Double.init), let lo = item("mlon").flatMap(Double.init),
           let p = valid(la, lo) {
            return (p.lat, p.lon, nil)
        }
        if let m = firstMatch(#"map=\d+(?:\.\d+)?/(-?\d{1,2}\.\d+)/(-?\d{1,3}\.\d+)"#, in: s),
           let p = valid(m[0], m[1]) {
            return (p.lat, p.lon, nil)
        }
        // Google: …/@14.6349,-90.5069,17z
        if let m = firstMatch(#"@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)"#, in: s),
           let p = valid(m[0], m[1]) {
            return (p.lat, p.lon, placeName)
        }
        // Google: …/search/14.6349,+-90.5069  o  /place/14.6349,-90.5069
        if let m = firstMatch(#"/(?:search|place|dir/[^/]*)/(-?\d{1,2}\.\d+),\+?\s*(-?\d{1,3}\.\d+)"#, in: s),
           let p = valid(m[0], m[1]) {
            return (p.lat, p.lon, nil)
        }
        return nil
    }

    /// «https://www.google.com/maps/place/Pollo+Campero+Zona+10/@…» → «Pollo Campero Zona 10».
    static func googlePlaceName(_ url: URL) -> String? {
        let parts = url.path.components(separatedBy: "/")
        guard let i = parts.firstIndex(of: "place"), i + 1 < parts.count else { return nil }
        let raw = parts[i + 1].replacingOccurrences(of: "+", with: " ")
        let name = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.hasPrefix("@") || pair(name) != nil { return nil }
        return name
    }

    /// Texto antes del enlace en lo que comparte Google Maps («Pollo Campero\nhttps://…»).
    static func nameBeforeLink(_ text: String) -> String? {
        guard let r = text.range(of: "http") else { return nil }
        let before = text[..<r.lowerBound]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = before.first, first.count <= 80 else { return nil }
        return first
    }

    // MARK: - Números

    /// «14.6349, -90.5069» o «14.6349 -90.5069». Pide decimales para no confundir números
    /// sueltos («zona 10 5») con coordenadas.
    static func pair(_ text: String) -> (lat: Double, lon: Double)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = wholeMatch(#"^\(?\s*(-?\d{1,3}\.\d+)\s*[,;\s]\s*\+?(-?\d{1,3}\.\d+)\s*\)?$"#, in: t) else { return nil }
        return valid(m[0], m[1])
    }

    /// 14°38'05.6"N 90°30'24.8"W (también con ’ ” y sin segundos).
    static func dms(_ text: String) -> (lat: Double, lon: Double)? {
        let unit = #"(\d{1,3})\s*[°º]\s*(?:(\d{1,2}(?:[.,]\d+)?)\s*['’′])?\s*(?:(\d{1,2}(?:[.,]\d+)?)\s*(?:"|”|″|''))?\s*([NSEWOnsewo])"#
        guard let re = try? NSRegularExpression(pattern: unit) else { return nil }
        let ns = text as NSString
        let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard found.count == 2 else { return nil }
        var lat: Double?
        var lon: Double?
        for m in found {
            func g(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r).replacingOccurrences(of: ",", with: ".")
            }
            guard let d = g(1).flatMap(Double.init), let hemi = g(4)?.uppercased() else { return nil }
            var v = d + (g(2).flatMap(Double.init) ?? 0) / 60 + (g(3).flatMap(Double.init) ?? 0) / 3600
            if hemi == "S" || hemi == "W" || hemi == "O" { v = -v }
            if hemi == "N" || hemi == "S" { lat = v } else { lon = v }
        }
        guard let la = lat, let lo = lon else { return nil }
        return valid(la, lo)
    }

    private static func valid(_ a: String, _ b: String) -> (lat: Double, lon: Double)? {
        guard let x = Double(a), let y = Double(b) else { return nil }
        return valid(x, y)
    }

    /// Acepta latitud y longitud en orden normal; si vienen al revés (algunas apps ponen la
    /// longitud primero) y solo así tienen sentido, las voltea.
    private static func valid(_ a: Double, _ b: Double) -> (lat: Double, lon: Double)? {
        if abs(a) <= 90, abs(b) <= 180, !(a == 0 && b == 0) { return (a, b) }
        if abs(b) <= 90, abs(a) <= 180 { return (b, a) }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static func wholeMatch(_ pattern: String, in text: String) -> [String]? {
        firstMatch(pattern, in: text)
    }
}

/// Abre un enlace corto (maps.app.goo.gl…) siguiendo sus redirecciones hasta que alguna
/// dirección trae coordenadas. Solo mira las direcciones, no lee el contenido de las páginas.
final class ShortLinkResolver: NSObject, URLSessionTaskDelegate {
    private var session: URLSession!
    private var done: ((Double, Double, String?) -> Void)?
    private var fail: (() -> Void)?
    private var finished = false
    private var task: URLSessionTask?

    func resolve(_ url: URL, done: @escaping (Double, Double, String?) -> Void, fail: @escaping () -> Void) {
        self.done = done
        self.fail = fail
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        let t = session.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self = self, !self.finished else { return }
                if let final = response?.url, self.check(final) { return }
                self.finish(nil)
            }
        }
        task = t
        t.resume()
    }

    func cancel() {
        finished = true
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let next = request.url, check(next) {
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    /// Revisa una dirección (y la dirección que Google guarda en «continue» en su página de
    /// consentimiento).
    private func check(_ url: URL) -> Bool {
        var candidates = [url]
        if let cont = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "continue" })?.value, let inner = URL(string: cont) {
            candidates.append(inner)
        }
        for u in candidates {
            if let hit = PlaceInput.coordinates(inURL: u) {
                finish((hit.lat, hit.lon, hit.name))
                return true
            }
        }
        return false
    }

    private func finish(_ hit: (Double, Double, String?)?) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        if let h = hit { done?(h.0, h.1, h.2) } else { fail?() }
        done = nil
        fail = nil
    }
}
