// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Combine

/// Registro en pantalla. Es el único canal de diagnóstico: el usuario lo copia y lo envía.
/// Se puede escribir desde cualquier hilo; `lines` (para la interfaz) se actualiza en el principal.
final class LogBus: ObservableObject {
    static let shared = LogBus()

    @Published private(set) var lines: [String] = []

    private let lock = NSLock()
    private var buffer: [String] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// 0.7.4: las claves que manda la moto (contraseña del servicio, la de actualizaciones…)
    /// no se escriben en el registro, para poder compartirlo. Solo cambia el texto del
    /// registro: lo que se envía y recibe de la moto es igual.
    private static let secretPattern = try? NSRegularExpression(
        pattern: #"("(?:password|passwd|pwd|pass|btPin|pin|token|secret|secretKey|privateKey)"\s*:\s*")([^"]*)(")"#,
        options: [.caseInsensitive])

    static func redact(_ text: String) -> String {
        guard let re = secretPattern, text.contains("\"") else { return text }
        let ns = text as NSString
        return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length),
                                           withTemplate: "$1•••$3")
    }

    func log(_ message: String) {
        let message = LogBus.redact(message)
        lock.lock()
        let line = formatter.string(from: Date()) + " " + message
        buffer.append(line)
        if buffer.count > 3000 {
            buffer.removeFirst(1000)
        }
        let snapshot = buffer
        lock.unlock()
        NSLog("%@", line)
        DispatchQueue.main.async {
            self.lines = snapshot
        }
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        DispatchQueue.main.async { self.lines.removeAll() }
    }

    /// Las últimas `count` líneas.
    func recent(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(buffer.suffix(count))
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.joined(separator: "\n")
    }
}

func logLine(_ message: String) {
    LogBus.shared.log(message)
}
