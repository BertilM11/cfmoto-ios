// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Darwin

enum SockError: Error, CustomStringConvertible {
    case io(String, Int32)
    case timeout(String)

    var description: String {
        switch self {
        case .io(let what, let code):
            return "\(what): \(String(cString: strerror(code))) (errno \(code))"
        case .timeout(let what):
            return "\(what): tiempo agotado"
        }
    }
}

func makeSockAddr(_ ip: String, _ port: UInt16) -> sockaddr_in {
    var a = sockaddr_in()
    a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_family = sa_family_t(AF_INET)
    a.sin_port = port.bigEndian
    a.sin_addr.s_addr = inet_addr(ip)
    return a
}

func ipString(hostOrder v: UInt32) -> String {
    return "\((v >> 24) & 255).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)"
}

/// Socket TCP bloqueante. Las escrituras van bajo un candado para que el latido y las
/// respuestas del bucle de lectura no se mezclen.
final class TcpSocket {
    let fd: Int32
    var peer: String = "?"

    private let writeLock = NSLock()
    private let closeLock = NSLock()
    private var closed = false

    init(fd: Int32) {
        self.fd = fd
        var one: Int32 = 1
        let len = socklen_t(MemoryLayout<Int32>.size)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, len)
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, len)
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func connect(host: String, port: UInt16, bindTo: String?, timeoutMs: Int32) throws -> TcpSocket {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { throw SockError.io("socket", errno) }

        if let local = bindTo {
            var la = makeSockAddr(local, 0)
            _ = withUnsafePointer(to: &la) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = makeSockAddr(host, port)
        let r = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r != 0 {
            let e = errno
            if e != EINPROGRESS {
                Darwin.close(fd)
                throw SockError.io("connect", e)
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let pr = poll(&pfd, 1, timeoutMs)
            if pr <= 0 {
                Darwin.close(fd)
                throw SockError.timeout("connect")
            }
            var soerr: Int32 = 0
            var slen = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen)
            if soerr != 0 {
                Darwin.close(fd)
                throw SockError.io("connect", soerr)
            }
        }
        _ = fcntl(fd, F_SETFL, flags)

        let s = TcpSocket(fd: fd)
        s.peer = "\(host):\(port)"
        return s
    }

    func setReadTimeout(seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Lee exactamente `n` bytes. Devuelve nil si el otro lado cierra, hay error o vence el tiempo.
    func readFully(_ n: Int) -> Data? {
        if n == 0 { return Data() }
        var buf = [UInt8](repeating: 0, count: n)
        var got = 0
        while got < n {
            let r = buf.withUnsafeMutableBytes { p -> Int in
                Darwin.recv(fd, p.baseAddress! + got, n - got, 0)
            }
            if r > 0 {
                got += r
            } else if r < 0 && errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        return Data(buf)
    }

    func writeAll(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < p.count {
                let r = Darwin.send(fd, p.baseAddress! + sent, p.count - sent, 0)
                if r > 0 {
                    sent += r
                } else if r < 0 && errno == EINTR {
                    continue
                } else {
                    throw SockError.io("send", errno)
                }
            }
        }
    }

    var isClosed: Bool {
        closeLock.lock()
        defer { closeLock.unlock() }
        return closed
    }

    func close() {
        closeLock.lock()
        let already = closed
        closed = true
        closeLock.unlock()
        if already { return }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

final class TcpListener {
    let fd: Int32
    let port: UInt16
    private var open = true
    private let lock = NSLock()

    init(port: UInt16) throws {
        self.port = port
        fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { throw SockError.io("socket", errno) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = makeSockAddr("0.0.0.0", port)
        let b = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if b != 0 {
            let e = errno
            Darwin.close(fd)
            throw SockError.io("bind :\(port)", e)
        }
        if Darwin.listen(fd, 16) != 0 {
            let e = errno
            Darwin.close(fd)
            throw SockError.io("listen :\(port)", e)
        }
    }

    private var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    /// Espera una conexión entrante. Devuelve nil cuando el listener se cierra.
    func accept() -> TcpSocket? {
        while isOpen {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, 500)
            if pr <= 0 { continue }
            if !isOpen { return nil }
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let c = withUnsafeMutablePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(fd, $0, &len)
                }
            }
            if c < 0 { continue }
            let s = TcpSocket(fd: c)
            let ip = ipString(hostOrder: UInt32(bigEndian: addr.sin_addr.s_addr))
            s.peer = "\(ip):\(UInt16(bigEndian: addr.sin_port))"
            return s
        }
        return nil
    }

    func close() {
        lock.lock()
        let wasOpen = open
        open = false
        lock.unlock()
        if wasOpen { Darwin.close(fd) }
    }
}

struct WifiInfo {
    let iface: String
    let ip: String
    let gateway: String
}

/// Direcciones IPv4 de las interfaces Wi-Fi (en*). La moto es el host ".1" de nuestra subred.
func wifiInterfaces() -> [WifiInfo] {
    var result: [WifiInfo] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0 else { return result }
    defer { freeifaddrs(ifap) }

    var cursor = ifap
    while let cur = cursor {
        let ifa = cur.pointee
        cursor = ifa.ifa_next
        guard let sa = ifa.ifa_addr, Int32(sa.pointee.sa_family) == AF_INET else { continue }
        let name = String(cString: ifa.ifa_name)
        guard name.hasPrefix("en") else { continue }

        let addrNet = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        var maskNet: in_addr_t = inet_addr("255.255.255.0")
        if let nm = ifa.ifa_netmask {
            maskNet = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        }
        let ip = UInt32(bigEndian: addrNet)
        var mask = UInt32(bigEndian: maskNet)
        if mask == 0 { mask = 0xFFFF_FF00 }
        if (ip >> 24) == 127 || (ip >> 16) == 0xA9FE { continue }
        let gw = (ip & mask) | 1
        result.append(WifiInfo(iface: name, ip: ipString(hostOrder: ip), gateway: ipString(hostOrder: gw)))
    }
    return result.sorted { $0.iface < $1.iface }
}
