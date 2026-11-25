// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.9.0: letra de la canción que suena, sincronizada por líneas (formato LRC). Aquí solo el
// modelo y la lectura del formato (sin red): lo usan el dibujo de la moto y las pruebas.
// La descarga está en LyricsService.swift (LRCLIB). La app no guarda letras en el repositorio.
import Foundation

struct LyricLine: Equatable {
    /// Segundo de la canción en que empieza la línea.
    var time: Double
    var text: String
}

struct LyricsSnapshot {
    /// Canción a la que pertenece (`LyricsSnapshot.key(...)`): si cambia la canción, no se muestra.
    var key: String
    var lines: [LyricLine]
    /// false: letra sin tiempos (no se muestra en la moto: no se sabría qué línea va).
    var synced: Bool
    var source = "LRCLIB"

    static func key(title: String, artist: String) -> String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    static func key(_ m: MusicSnapshot) -> String { key(title: m.title, artist: m.artist) }

    /// La línea que va en `position` (segundos): la última que ya empezó; nil antes de la primera.
    func index(at position: Double) -> Int? {
        guard synced, !lines.isEmpty else { return nil }
        var lo = 0
        var hi = lines.count - 1
        var found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position + 0.15 {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }
}

enum LRC {
    /// Lee un texto LRC: «[mm:ss.xx] texto» (puede haber varias marcas por línea). Se omiten las
    /// etiquetas de información ([ar:…], [ti:…]) y las líneas vacías.
    static func parse(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = time(tag) { times.append(t) }
                rest = rest[rest.index(after: close)...]
            }
            let line = rest.trimmingCharacters(in: .whitespaces)
            guard !times.isEmpty, !line.isEmpty else { continue }
            for t in times { out.append(LyricLine(time: t, text: line)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// «mm:ss», «mm:ss.xx» o «mm:ss:xx» → segundos.
    static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let m = Double(parts[0]) else { return nil }
        var secText = String(parts[1])
        if parts.count == 3 { secText += "." + parts[2] }
        guard let s = Double(secText), m >= 0, s >= 0, s < 60 else { return nil }
        return m * 60 + s
    }
}
