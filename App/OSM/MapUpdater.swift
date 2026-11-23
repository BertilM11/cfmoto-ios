// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CryptoKit
import SwiftUI

/// 0.8.1: actualizar el mapa de Guatemala desde la app, sin reinstalarla.
///
/// Solo se ofrecen los mapas publicados en la rama principal del proyecto
/// (`Tools/OSM/Guatemala.cfmap.sha256`), no los de prueba. El archivo se baja de la
/// publicación `mapa-guatemala` de GitHub, se comprueba su huella SHA-256 y que se pueda
/// leer, y se usa al volver a abrir la app. «Volver al mapa incluido» lo borra.
final class MapUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = MapUpdater()

    static let pinURL = URL(string: "https://raw.githubusercontent.com/BertilM11/cfmoto-ios/main/Tools/OSM/Guatemala.cfmap.sha256")!
    static func fileURL(sha: String) -> URL {
        URL(string: "https://github.com/BertilM11/cfmoto-ios/releases/download/mapa-guatemala/Guatemala-\(sha.prefix(8)).cfmap")!
    }
    private static let shaKey = "mapaDescargadoSha"
    private static let bundledShaKey = "mapaIncluidoSha"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(sha: String)
        case downloading(Double)
        /// Listo: se usará al volver a abrir la app.
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var expected = ""
    private var session: URLSession?

    /// Huella del mapa en uso (descargado o el de la app).
    func currentSha() -> String? {
        if OSMMapData.usingDownloaded, let s = UserDefaults.standard.string(forKey: Self.shaKey) { return s }
        if let cached = UserDefaults.standard.string(forKey: Self.bundledShaKey + appBuild) { return cached }
        guard let url = Bundle.main.url(forResource: "Guatemala", withExtension: "cfmap"),
              let sha = Self.sha256(of: url) else { return nil }
        UserDefaults.standard.set(sha, forKey: Self.bundledShaKey + appBuild)
        return sha
    }

    private var appBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    func check() {
        state = .checking
        var request = URLRequest(url: Self.pinURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("MotoLink", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let text = ok ? data.flatMap { String(data: $0, encoding: .utf8) } : nil
            let sha = text.flatMap { Self.parsePin($0) }
            DispatchQueue.global(qos: .userInitiated).async {
                let current = self?.currentSha()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard let sha = sha else {
                        self.state = .failed("No se pudo revisar (¿sin internet?)")
                        return
                    }
                    if sha == current || (sha == UserDefaults.standard.string(forKey: Self.shaKey) && FileManager.default.fileExists(atPath: OSMMapData.downloadedURL.path)) {
                        self.state = sha == current ? .upToDate : .ready
                    } else {
                        self.state = .available(sha: sha)
                    }
                    logLine("[MAPA] revisión: publicado \(sha.prefix(8)), en uso \(current?.prefix(8) ?? "?")")
                }
            }
        }.resume()
    }

    func download() {
        guard case let .available(sha) = state else { return }
        expected = sha
        state = .downloading(0)
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        s.downloadTask(with: Self.fileURL(sha: sha)).resume()
        logLine("[MAPA] descargando \(sha.prefix(8))")
    }

    /// Borra el mapa descargado: al volver a abrir la app se usa el que viene con ella.
    func revert() {
        try? FileManager.default.removeItem(at: OSMMapData.downloadedURL)
        UserDefaults.standard.removeObject(forKey: Self.shaKey)
        state = .idle
        logLine("[MAPA] se volverá al mapa incluido en la app")
    }

    var hasDownloaded: Bool { FileManager.default.fileExists(atPath: OSMMapData.downloadedURL.path) }

    // MARK: - Descarga

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        state = .downloading(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // El archivo temporal se borra al volver de esta función: se mueve antes de revisarlo.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("mapa-nuevo.cfmap")
        try? FileManager.default.removeItem(at: staging)
        guard (200..<300).contains(status), (try? FileManager.default.moveItem(at: location, to: staging)) != nil else {
            state = .failed("La descarga falló (\(status))")
            return
        }
        let expected = self.expected
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.install(staging, expected: expected)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = result {
                    self.state = .failed(error)
                    logLine("[MAPA] descarga rechazada: \(error)")
                } else {
                    UserDefaults.standard.set(expected, forKey: Self.shaKey)
                    self.state = .ready
                    logLine("[MAPA] mapa \(expected.prefix(8)) listo; se usa al volver a abrir la app")
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, case .downloading = state {
            state = .failed("La descarga se cortó: \(error.localizedDescription)")
        }
        session.finishTasksAndInvalidate()
    }

    /// Revisa la huella y que el mapa se pueda leer; después lo pone en su lugar. Devuelve el
    /// error, o nil si quedó instalado.
    static func install(_ file: URL, expected: String) -> String? {
        guard let sha = sha256(of: file), sha == expected else { return "La huella del archivo no coincide" }
        guard let map = OSMMapData(url: file), map.version >= 2, map.placeCount > 1000 else { return "El archivo no es un mapa válido" }
        _ = map
        let dest = OSMMapData.downloadedURL
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: file, to: dest)
        } catch {
            return "No se pudo guardar el mapa"
        }
        return nil
    }

    /// «08b19afe…  Guatemala.cfmap» → «08b19afe…» (64 caracteres hexadecimales).
    static func parsePin(_ text: String) -> String? {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first ?? ""
        let hex = first.lowercased()
        return hex.count == 64 && hex.allSatisfy({ $0.isHexDigit }) ? hex : nil
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 0.8.1: tarjeta para revisar y descargar el mapa nuevo.
struct MapUpdateCard: View {
    @ObservedObject private var updater = MapUpdater.shared

    var body: some View {
        Card {
            Text("Mapa de Guatemala").font(.headline)
            if let map = OSMMapData.current {
                Text("Datos de OpenStreetMap del \(Self.day(map.date)) · \(map.placeCount.formatted()) lugares · \(OSMMapData.usingDownloaded ? "descargado" : "incluido en la app")")
                    .font(.caption).foregroundColor(Brand.dim)
            }
            switch updater.state {
            case .idle:
                button("Buscar actualización", "arrow.triangle.2.circlepath") { updater.check() }
            case .checking:
                ProgressView("Revisando…")
            case .upToDate:
                Label("Ya tenés el mapa más nuevo", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            case .available:
                Text("Hay un mapa más nuevo (unos 26 MB). Mejor con Wi-Fi.").font(.footnote)
                button("Descargar", "arrow.down.circle.fill") { updater.download() }
            case .downloading(let f):
                ProgressView(value: f) { Text("Descargando… \(Int(f * 100)) %").font(.footnote) }
            case .ready:
                Label("Listo: se usa al cerrar y volver a abrir la app", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            case .failed(let why):
                Text(why).font(.footnote).foregroundColor(.orange)
                button("Intentar de nuevo", "arrow.triangle.2.circlepath") { updater.check() }
            }
            if updater.hasDownloaded {
                Button("Volver al mapa incluido en la app", role: .destructive) { updater.revert() }
                    .font(.footnote)
            }
        }
        .font(.subheadline)
        .tint(Brand.blue)
    }

    private func button(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_GT")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f.string(from: d)
    }
}
