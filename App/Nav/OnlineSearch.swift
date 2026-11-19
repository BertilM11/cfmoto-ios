// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// 0.7.2: búsqueda en internet en OpenStreetMap (Nominatim), solo cuando el usuario la pide
/// con «Buscar en internet»: encuentra direcciones y lugares que no vienen en el mapa guardado.
/// Respeta las reglas de uso de Nominatim: una consulta por toque (nunca al escribir cada
/// letra), identificación de la app y el aviso «© OpenStreetMap».
enum OnlineSearch {
    struct Place: Equatable {
        let title: String
        let subtitle: String
        let lat: Double
        let lon: Double
    }

    static let endpoint = "https://nominatim.openstreetmap.org/search"

    static func request(_ text: String, near: GeoPoint?) -> URLRequest? {
        guard var comps = URLComponents(string: endpoint) else { return nil }
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "countrycodes", value: "gt"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "accept-language", value: "es"),
            URLQueryItem(name: "addressdetails", value: "0"),
        ]
        if let p = near {
            // Prefiere lo cercano (sin limitarse a esa zona).
            let d = 0.6
            items.append(URLQueryItem(name: "viewbox", value: String(format: "%.4f,%.4f,%.4f,%.4f", p.lon - d, p.lat + d, p.lon + d, p.lat - d)))
        }
        comps.queryItems = items
        guard let url = comps.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 10)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7"
        r.setValue("MotoLink/\(version) (+https://github.com/BertilM11/cfmoto-ios)", forHTTPHeaderField: "User-Agent")
        r.setValue("es", forHTTPHeaderField: "Accept-Language")
        return r
    }

    /// Lee la respuesta de Nominatim. «display_name» trae «Nombre, calle, zona, ciudad,
    /// departamento, país»: el nombre va de título y lo demás (sin el país) de detalle.
    static func parse(_ data: Data) -> [Place] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [Place] = []
        for item in list {
            func num(_ k: String) -> Double? {
                if let s = item[k] as? String { return Double(s) }
                return item[k] as? Double
            }
            guard let lat = num("lat"), let lon = num("lon") else { continue }
            let display = (item["display_name"] as? String) ?? ""
            var parts = display.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let last = parts.last, last == "Guatemala", parts.count > 1 { parts.removeLast() }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? parts.first ?? "Lugar"
            if parts.first == name { parts.removeFirst() }
            let detail = parts.prefix(3).joined(separator: ", ")
            let place = Place(title: name, subtitle: detail, lat: lat, lon: lon)
            if !out.contains(where: { $0.title == place.title && abs($0.lat - lat) < 0.0005 && abs($0.lon - lon) < 0.0005 }) {
                out.append(place)
            }
        }
        return out
    }

    /// Hace la consulta. `done` se llama en el hilo principal (nil = sin conexión o error).
    @discardableResult
    static func search(_ text: String, near: GeoPoint?, done: @escaping ([Place]?) -> Void) -> URLSessionDataTask? {
        guard let r = request(text, near: near) else {
            done(nil)
            return nil
        }
        let task = URLSession.shared.dataTask(with: r) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let found = ok ? data.map(parse) : nil
            DispatchQueue.main.async { done(found) }
        }
        task.resume()
        return task
    }
}
