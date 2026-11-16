// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// La extensión de transmisión no tiene pantalla propia. Para poder ver su registro, sirve el
/// texto en el puerto 10950 del propio iPhone y la app lo lee por 127.0.0.1.
/// Formato: [longitud u32 LE][texto UTF-8] y se cierra la conexión.
enum LogShare {
    static let port: UInt16 = 10950

    /// Lado de la app: pide el registro a la extensión. nil si la extensión no está activa.
    static func fetch() -> String? {
        guard let s = try? TcpSocket.connect(host: "127.0.0.1", port: port, bindTo: nil, timeoutMs: 300) else {
            return nil
        }
        defer { s.close() }
        s.setReadTimeout(seconds: 2)
        guard let h = s.readFully(4) else { return nil }
        let n = Int(h.le32(0))
        if n == 0 { return "" }
        if n > 4_000_000 { return nil }
        guard let body = s.readFully(n) else { return nil }
        return String(decoding: body, as: UTF8.self)
    }
}

/// Lado de la extensión.
final class LogServer {
    private var listener: TcpListener?
    private let lock = NSLock()
    private var open = true

    init?() {
        guard let l = try? TcpListener(port: LogShare.port) else {
            logLine("[registro] no se pudo abrir el puerto \(LogShare.port) para compartir el registro")
            return nil
        }
        listener = l
        Thread.detachNewThread { [weak self] in self?.loop(l) }
    }

    private func loop(_ l: TcpListener) {
        while true {
            lock.lock()
            let isOpen = open
            lock.unlock()
            if !isOpen { break }
            guard let client = l.accept() else { break }
            let body = Data(LogBus.shared.text.utf8)
            var d = Data(capacity: 4 + body.count)
            d.appendLE32(UInt32(body.count))
            d.append(body)
            try? client.writeAll(d)
            client.close()
        }
    }

    func close() {
        lock.lock()
        open = false
        lock.unlock()
        listener?.close()
        listener = nil
    }
}
