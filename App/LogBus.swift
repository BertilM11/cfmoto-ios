// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Registro en pantalla. Es el único canal de diagnóstico: el usuario lo copia y lo envía.
final class LogBus: ObservableObject {
    static let shared = LogBus()

    @Published private(set) var lines: [String] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func log(_ message: String) {
        let line = formatter.string(from: Date()) + " " + message
        NSLog("%@", line)
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 3000 {
                self.lines.removeFirst(1000)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { self.lines.removeAll() }
    }

    var text: String { lines.joined(separator: "\n") }
}

func logLine(_ message: String) {
    LogBus.shared.log(message)
}
