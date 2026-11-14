// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Formato de trama del plano de control EasyConn / Carbit PXC, según la documentación
// de ingeniería inversa de OpenCfMoto (https://github.com/zanderp/open-cfmoto).
import Foundation

extension Data {
    mutating func appendLE32(_ v: UInt32) {
        Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLE16(_ v: UInt16) {
        Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) }
    }

    func le32(_ offset: Int) -> UInt32 {
        let b = startIndex + offset
        return UInt32(self[b]) | (UInt32(self[b + 1]) << 8) | (UInt32(self[b + 2]) << 16) | (UInt32(self[b + 3]) << 24)
    }

    func le16(_ offset: Int) -> UInt16 {
        let b = startIndex + offset
        return UInt16(self[b]) | (UInt16(self[b + 1]) << 8)
    }

    var asText: String {
        if isEmpty { return "" }
        return String(data: self, encoding: .utf8) ?? "<\(count) bytes>"
    }

    func hexPrefix(_ n: Int) -> String {
        return prefix(n).map { String(format: "%02x", $0) }.joined()
    }
}

func hex(_ v: UInt32) -> String {
    return "0x" + String(v, radix: 16)
}

/// Cabecera de 16 bytes (little-endian): cmd | totalLen | cmd XOR totalLen | 0, y luego el cuerpo.
struct PxcFrame {
    static let mdnsRespond: UInt32 = 0x7000_0010
    static let mdnsRespondAck: UInt32 = 0x7000_0011
    static let heartbeat: UInt32 = 0x7000_0000
    static let heartbeatAck: UInt32 = 0x7000_0001
    static let channelCarCtrl: UInt32 = 0x10000
    static let channelCarData: UInt32 = 0x20000
    static let clientInfo: UInt32 = 0x10010
    static let clientInfoReply: UInt32 = 0x10011
    static let querySpeed: UInt32 = 0x10690
    static let checkSn: UInt32 = 0x103e0
    static let checkSnResult: UInt32 = 0x201c0
    static let huTimeSync: UInt32 = 0x10600
    static let huQueryTime: UInt32 = 0x10450

    let cmd: UInt32
    let payload: Data

    init(_ cmd: UInt32, _ payload: Data = Data()) {
        self.cmd = cmd
        self.payload = payload
    }

    init(_ cmd: UInt32, text: String) {
        self.cmd = cmd
        self.payload = Data(text.utf8)
    }

    func encoded() -> Data {
        let total = UInt32(16 + payload.count)
        var d = Data(capacity: Int(total))
        d.appendLE32(cmd)
        d.appendLE32(total)
        d.appendLE32(cmd ^ total)
        d.appendLE32(0)
        d.append(payload)
        return d
    }

    func write(to sock: TcpSocket) throws {
        try sock.writeAll(encoded())
    }

    enum ReadError: Error {
        case badMagic(UInt32, UInt32, UInt32)
        case shortPayload(Int)
    }

    /// Devuelve nil si la conexión se cerró antes de una cabecera completa.
    static func read(from sock: TcpSocket) throws -> PxcFrame? {
        guard let h = sock.readFully(16) else { return nil }
        let cmd = h.le32(0)
        let total = h.le32(4)
        let magic = h.le32(8)
        if (cmd ^ total) != magic {
            throw ReadError.badMagic(cmd, total, magic)
        }
        let plen = total >= 16 ? Int(total - 16) : 0
        if plen > 4_000_000 { throw ReadError.shortPayload(plen) }
        guard let body = sock.readFully(plen) else { throw ReadError.shortPayload(plen) }
        return PxcFrame(cmd, body)
    }
}

/// Respuesta 0x10601 a la sincronización de hora de la moto (0x10600).
/// Cabecera de 16 bytes + "yyyy-MM-dd HH:mm:ss.SSS000000". Se devuelve la hora de la moto tal
/// cual, salvo que venga vacía o en 1970: entonces se pone la hora del teléfono. Nunca vacía.
enum HuTimeSync {
    private static let timeOffset = 16
    private static let timeLength = 29

    static func ack(for request: Data) -> Data {
        let len = max(45, request.count)
        var out = [UInt8](repeating: 0, count: len)
        let req = [UInt8](request)
        for i in 0..<min(req.count, len) { out[i] = req[i] }

        if req.count < timeOffset {
            var head = Data()
            head.appendLE32(UInt32(bitPattern: -2))
            head.appendLE32(0)
            head.appendLE32(1)
            head.appendLE32(0)
            for (i, b) in head.enumerated() { out[i] = b }
        }

        if !shouldEcho(req) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let stamp = Array((f.string(from: Date()) + "000000").utf8)
            for i in 0..<min(timeLength, stamp.count) { out[timeOffset + i] = stamp[i] }
        }
        return Data(out)
    }

    private static func shouldEcho(_ req: [UInt8]) -> Bool {
        if req.count < timeOffset + 4 { return false }
        let n = min(timeLength, req.count - timeOffset)
        let bytes = Array(req[timeOffset..<(timeOffset + n)])
        let stamp = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        if stamp.isEmpty { return false }
        if let year = Int(stamp.prefix(4)), (1969...1971).contains(year) { return false }
        return true
    }
}
