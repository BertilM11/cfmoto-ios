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

    func log(_ message: String) {
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
