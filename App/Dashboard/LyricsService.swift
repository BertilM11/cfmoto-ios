// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.9.0: busca la letra sincronizada de la canción que suena en LRCLIB (lrclib.net, servicio
// gratuito y abierto, sin clave). Solo se pide con «Letra en lugar de avisos» encendido y con
// internet; una consulta por canción, guardada en memoria mientras la app está abierta. Ni
// Spotify ni Apple Music dan la letra a otras apps. Las letras tienen derechos de autor: la app
// solo las consulta para mostrarlas en la moto; no se guardan en el repositorio.
import Foundation

final class LyricsService {
    static let shared = LyricsService()

    private var cache: [String: LyricsSnapshot] = [:]
    private var notFound: Set<String> = []
    private var order: [String] = []
    private var currentKey = ""
    private var task: URLSessionDataTask?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": "MotoLink (https://github.com/BertilM11/cfmoto-ios)"]
        return URLSession(configuration: c)
    }()

    /// Al encender o apagar la opción.
    func settingChanged(_ on: Bool) {
        DispatchQueue.main.async {
            if on {
                self.currentKey = ""
                self.trackChanged(DashState.shared.currentMusic())
            } else {
                self.task?.cancel()
                self.currentKey = ""
                DashState.shared.setLyrics(nil)
            }
        }
    }

    /// Cambió la canción (desde el hilo principal).
    func trackChanged(_ m: MusicSnapshot) {
        guard DashStore.shared.config.lyricsMode, m.available, !m.title.isEmpty else {
            if !currentKey.isEmpty {
                currentKey = ""
                DashState.shared.setLyrics(nil)
            }
            return
        }
        let key = LyricsSnapshot.key(m)
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()
        if let hit = cache[key] {
            DashState.shared.setLyrics(hit)
            return
        }
        DashState.shared.setLyrics(nil)
        if notFound.contains(key) { return }
        fetch(title: m.title, artist: m.artist, album: m.album, duration: m.duration, key: key)
    }

    // MARK: - LRCLIB

    private func fetch(title: String, artist: String, album: String, duration: Double, key: String) {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        c.queryItems = items
        guard let url = c.url else { return }
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            guard let self = self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, let data = data, let found = LyricsService.parseRecord(data, key: key) {
                self.finish(key, found)
            } else {
                // Sin coincidencia exacta: búsqueda por título (sin «- Remastered», «(feat. …)»…).
                self.search(title: LyricsService.cleanTitle(title), artist: artist, duration: duration, key: key)
            }
        }
        task?.resume()
    }

    private func search(title: String, artist: String, duration: Double, key: String) {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        guard let url = c.url else { return }
        let t = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if (error as? URLError)?.code == .cancelled { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let found = code == 200 ? data.flatMap { LyricsService.pickFromSearch($0, duration: duration, key: key) } : nil
            self.finish(key, found, offline: error != nil)
        }
        DispatchQueue.main.async { self.task = t }
        t.resume()
    }

    private func finish(_ key: String, _ found: LyricsSnapshot?, offline: Bool = false) {
        DispatchQueue.main.async {
            if let f = found {
                self.cache[key] = f
                self.order.append(key)
                if self.order.count > 40 { self.cache[self.order.removeFirst()] = nil }
                logLine("[LETRA] letra sincronizada encontrada (\(f.lines.count) líneas) · LRCLIB")
            } else if offline {
                logLine("[LETRA] sin internet: no se pudo buscar la letra")
            } else {
                self.notFound.insert(key)
                logLine("[LETRA] esta canción no tiene letra sincronizada en LRCLIB")
            }
            guard key == self.currentKey else { return }
            DashState.shared.setLyrics(found)
        }
    }

    // MARK: - Lectura de respuestas (puras)

    static func parseRecord(_ data: Data, key: String) -> LyricsSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return snapshot(from: obj, key: key)
    }

    static func pickFromSearch(_ data: Data, duration: Double, key: String) -> LyricsSnapshot? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let synced = arr.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false && ($0["instrumental"] as? Bool) != true }
        let best = synced.min { a, b in
            let da = abs(((a["duration"] as? Double) ?? 0) - duration)
            let db = abs(((b["duration"] as? Double) ?? 0) - duration)
            return da < db
        }
        guard let b = best else { return nil }
        // Si la duración no se parece (otra versión de la canción), la letra no iría a tiempo.
        if duration > 0, let d = b["duration"] as? Double, abs(d - duration) > 6 { return nil }
        return snapshot(from: b, key: key)
    }

    static func snapshot(from obj: [String: Any], key: String) -> LyricsSnapshot? {
        if (obj["instrumental"] as? Bool) == true { return nil }
        guard let lrc = obj["syncedLyrics"] as? String else { return nil }
        let lines = LRC.parse(lrc)
        guard lines.count >= 2 else { return nil }
        return LyricsSnapshot(key: key, lines: lines, synced: true)
    }

    /// Quita lo que suele sobrar en los títulos de Spotify para buscar mejor.
    static func cleanTitle(_ t: String) -> String {
        var s = t
        for sep in [" - ", " – ", " — "] {
            if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) }
        }
        if let r = s.range(of: " (feat", options: .caseInsensitive) { s = String(s[..<r.lowerBound]) }
        if let r = s.range(of: " [", options: .caseInsensitive) { s = String(s[..<r.lowerBound]) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
