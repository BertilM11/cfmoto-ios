// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Cliente EasyConn / Carbit PXC para pantallas CFMOTO, escrito para iOS a partir de la
// documentación y el comportamiento de OpenCfMoto (https://github.com/zanderp/open-cfmoto,
// AGPL-3.0-or-later, © Alexandru y colaboradores de OpenCfMoto).
//
// Topología: EL TELÉFONO ES EL SERVIDOR.
//  1. Abrir servidores TCP en 10920, 10921 y 10922.
//  2. Enviar un aviso (cmd 0x70000010, JSON) a moto:10930; la moto responde {"status":true}.
//  3. La moto se conecta DE VUELTA a nuestros puertos y dirige el saludo.
//  4. Por 10921/10920 negocia el vídeo y va pidiendo fotogramas H.264 de uno en uno.
import Foundation
import UIKit

final class BikeLink {
    static let portMediaData: UInt16 = 10920
    static let portMediaCtrl: UInt16 = 10921
    static let portPxcCtrl: UInt16 = 10922
    static let probePort: UInt16 = 10930
    /// La moto solo conoce la app oficial de Android, así que nos presentamos como ella.
    static let spoofedPackage = "com.cfmoto.cfmotointernational"

    var onStatus: ((String) -> Void)?

    private let lock = NSLock()
    private var running = false
    private var generation = 0
    private var listeners: [TcpListener] = []
    private var clients: [TcpSocket] = []
    private var probed = false
    private var everConnected = false
    private var reprobing = false
    private var myIp = ""
    private var bikeIp = ""
    private var negW = 800
    private var negH = 384
    private var encoder: H264Encoder?
    private var pattern: TestPattern?
    private var framesSent = 0
    private var heartbeatsSeen = 0
    private var timeSyncSeen = 0
    private var touchSeen = 0
    private let phoneUuid = UUID().uuidString.lowercased()

    // MARK: - Ciclo de vida

    private func alive(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return running && generation == gen
    }

    private func status(_ s: String) {
        onStatus?(s)
    }

    func start(manualBikeIp: String) {
        stop()

        logLine("---- CFMoto Link \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") ----")
        logLine("dispositivo: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")

        let interfaces = wifiInterfaces()
        if interfaces.isEmpty {
            logLine("!! no hay Wi-Fi con dirección IP. Conéctate primero a la red de la moto en Ajustes > Wi-Fi.")
            status("Sin Wi-Fi: conéctate a la red de la moto")
            return
        }
        for i in interfaces {
            logLine("interfaz \(i.iface): ip=\(i.ip) moto(supuesta)=\(i.gateway)")
        }
        let wifi = interfaces.first(where: { $0.iface == "en0" }) ?? interfaces[0]
        let manual = manualBikeIp.trimmingCharacters(in: .whitespaces)

        lock.lock()
        generation += 1
        let gen = generation
        running = true
        probed = false
        everConnected = false
        reprobing = false
        framesSent = 0
        heartbeatsSeen = 0
        timeSyncSeen = 0
        touchSeen = 0
        myIp = wifi.ip
        bikeIp = manual.isEmpty ? wifi.gateway : manual
        lock.unlock()

        logLine("nuestra IP=\(myIp)  IP de la moto=\(bikeIp)")
        logLine("clave RSA: \(RsaKeys.shared.bits) bits")
        if !bikeIp.hasPrefix("192.168.49.") {
            logLine("aviso: la red de la moto suele ser 192.168.49.x; comprueba que el Wi-Fi conectado es DIRECT-...-CFMOTO")
        }

        // Escuchar ANTES de avisar, para estar listos cuando la moto llame de vuelta.
        var opened: [TcpListener] = []
        for port in [BikeLink.portPxcCtrl, BikeLink.portMediaCtrl, BikeLink.portMediaData] {
            do {
                opened.append(try TcpListener(port: port))
            } catch {
                logLine("!! no se pudo abrir el puerto \(port): \(error)")
            }
        }
        if opened.count != 3 {
            for l in opened { l.close() }
            lock.lock()
            running = false
            lock.unlock()
            status("Error: puertos ocupados (cierra la app CFMOTO oficial)")
            return
        }
        lock.lock()
        listeners = opened
        lock.unlock()
        logLine("escuchando en los puertos 10922, 10921 y 10920")
        status("Avisando a la moto…")

        for l in opened {
            Thread.detachNewThread { [weak self] in self?.acceptLoop(l, gen) }
        }
        Thread.detachNewThread { [weak self] in self?.discover(gen) }
        Thread.detachNewThread { [weak self] in self?.statusLoop(gen) }
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        generation += 1
        let oldListeners = listeners
        let oldClients = clients
        listeners = []
        clients = []
        let oldPattern = pattern
        let oldEncoder = encoder
        pattern = nil
        encoder = nil
        lock.unlock()

        oldPattern?.stop()
        oldEncoder?.stop()
        for c in oldClients { c.close() }
        for l in oldListeners { l.close() }
        if wasRunning {
            logLine("detenido")
            status("Detenido")
        }
    }

    // MARK: - Aviso a la moto (puerto 10930)

    private func discover(_ gen: Int) {
        probe(gen, attempts: 6)
        if probed || !alive(gen) { return }

        // La moto no contestó en 10930: mirar qué puertos tiene abiertos para diagnosticar.
        logLine("[DISC] sin respuesta en \(bikeIp):10930; buscando puertos abiertos…")
        var open: [UInt16] = []
        let candidates: [UInt16] = Array(10915...10935) + [8200, 5000, 7000, 80]
        for port in candidates {
            if !alive(gen) { return }
            if let s = try? TcpSocket.connect(host: bikeIp, port: port, bindTo: nil, timeoutMs: 350) {
                open.append(port)
                s.close()
            }
        }
        logLine("[DISC] puertos abiertos en la moto: \(open.isEmpty ? "ninguno" : open.map { String($0) }.joined(separator: ", "))")
        if !alive(gen) { return }
        if !everConnected {
            logLine("!! la moto no respondió. Deja abierta la pantalla del código QR en la moto, comprueba el Wi-Fi y que aceptaste el permiso de red local.")
            status("La moto no respondió")
        }
    }

    private func probe(_ gen: Int, attempts: Int) {
        var attempt = 0
        while alive(gen) && attempt < attempts && !probed {
            attempt += 1
            logLine("[PROBE] intento #\(attempt) -> \(bikeIp):\(BikeLink.probePort)")
            do {
                let s = try TcpSocket.connect(host: bikeIp, port: BikeLink.probePort, bindTo: myIp, timeoutMs: 3000)
                defer { s.close() }
                s.setReadTimeout(seconds: 5)
                let json = "{\"phoneType\":\"Android\",\"packageName\":\"\(BikeLink.spoofedPackage)\"}"
                logLine("[PROBE] -> MDNS_RESPOND (0x70000010) \(json)")
                try PxcFrame(PxcFrame.mdnsRespond, text: json).write(to: s)
                if let resp = try PxcFrame.read(from: s) {
                    let body = resp.payload.asText
                    logLine("[PROBE] <- cmd=\(hex(resp.cmd)) \(body)")
                    if resp.cmd == PxcFrame.mdnsRespondAck && body.contains("true") {
                        logLine("[PROBE] *** ACEPTADO: la moto debería conectarse ahora a nuestros puertos ***")
                        probed = true
                        status("La moto aceptó; esperando su conexión…")
                    } else {
                        logLine("[PROBE] !! no aceptado: \(body)")
                    }
                } else {
                    logLine("[PROBE] la moto cerró sin responder")
                }
            } catch {
                logLine("[PROBE] falló: \(error)")
            }
            if probed { return }
            Thread.sleep(forTimeInterval: 0.75 * Double(attempt))
        }
    }

    // MARK: - Conexiones entrantes

    private func acceptLoop(_ listener: TcpListener, _ gen: Int) {
        let port = listener.port
        while alive(gen) {
            guard let client = listener.accept() else { break }
            if !alive(gen) {
                client.close()
                break
            }
            logLine("[:\(port)] <<< la moto se conectó desde \(client.peer)")
            lock.lock()
            clients.append(client)
            everConnected = true
            lock.unlock()
            Thread.detachNewThread { [weak self] in
                guard let self = self else { return }
                self.readLoop(port, client, gen)
                client.close()
                self.clientClosed(client, gen)
            }
        }
    }

    private func clientClosed(_ client: TcpSocket, _ gen: Int) {
        lock.lock()
        clients.removeAll { $0 === client }
        let none = clients.isEmpty
        let shouldReprobe = none && running && generation == gen && everConnected && !reprobing
        if shouldReprobe { reprobing = true }
        lock.unlock()
        if !shouldReprobe { return }

        // La moto soltó todas las conexiones pero seguimos escuchando: volver a avisarla.
        status("Enlace perdido; reintentando…")
        Thread.detachNewThread { [weak self] in
            guard let self = self else { return }
            var tries = 0
            while self.alive(gen) && tries < 10 {
                tries += 1
                self.lock.lock()
                let connected = !self.clients.isEmpty
                self.lock.unlock()
                if connected { break }
                logLine("[reconexión] enlace perdido; nuevo aviso (intento \(tries)/10)")
                Thread.sleep(forTimeInterval: min(0.5 + 0.5 * Double(tries), 4.0))
                if !self.alive(gen) { break }
                self.probed = false
                self.framesSent = 0
                self.probe(gen, attempts: 2)
                Thread.sleep(forTimeInterval: 2.5)
            }
            self.lock.lock()
            self.reprobing = false
            self.lock.unlock()
        }
    }

    private func readLoop(_ port: UInt16, _ sock: TcpSocket, _ gen: Int) {
        let tag = ":\(port)"
        if port == BikeLink.portPxcCtrl {
            logLine("[\(tag)] plano de control (cabecera de 16 bytes)")
            while alive(gen) {
                let frame: PxcFrame
                do {
                    guard let f = try PxcFrame.read(from: sock) else {
                        logLine("[\(tag)] la moto cerró la conexión")
                        return
                    }
                    frame = f
                } catch {
                    logLine("[\(tag)] trama inválida: \(error)")
                    return
                }
                do {
                    try handleControl(tag, frame, sock, gen)
                } catch {
                    logLine("[\(tag)] error al responder \(hex(frame.cmd)): \(error)")
                    return
                }
            }
        } else {
            logLine("[\(tag)] plano de vídeo (cabecera de 8 bytes)")
            while alive(gen) {
                guard let h = sock.readFully(8) else {
                    logLine("[\(tag)] la moto cerró la conexión de vídeo")
                    return
                }
                let cmdType = Int(Int16(bitPattern: h.le16(0)))
                let len = Int(h.le16(2))
                guard let body = sock.readFully(len) else {
                    logLine("[\(tag)] cuerpo incompleto (cmd \(cmdType), \(len) bytes)")
                    return
                }
                do {
                    try handleMedia(tag, cmdType, body, sock)
                } catch {
                    logLine("[\(tag)] error al responder cmd \(cmdType): \(error)")
                    return
                }
            }
        }
    }

    // MARK: - Plano de control (10922)

    private func handleControl(_ tag: String, _ frame: PxcFrame, _ sock: TcpSocket, _ gen: Int) throws {
        switch frame.cmd {
        case PxcFrame.channelCarCtrl:
            logLine("[\(tag)] la moto eligió CAR_CTRL (0x10000) -> 0x10001")
            try PxcFrame(frame.cmd + 1).write(to: sock)
            startHeartbeat(sock, "CAR_CTRL", gen)

        case PxcFrame.channelCarData:
            logLine("[\(tag)] la moto eligió CAR_DATA (0x20000) -> 0x20001")
            try PxcFrame(frame.cmd + 1).write(to: sock)
            startHeartbeat(sock, "CAR_DATA", gen)

        case PxcFrame.clientInfo:
            try onClientInfo(tag, frame, sock)

        case PxcFrame.querySpeed:
            logLine("[\(tag)] QUERY_SPEED \(frame.payload.asText) -> 0x10691")
            try PxcFrame(frame.cmd + 1).write(to: sock)

        case PxcFrame.checkSn:
            try onCheckSn(tag, frame, sock)

        case PxcFrame.heartbeat:
            heartbeatsSeen += 1
            if heartbeatsSeen <= 3 || heartbeatsSeen % 30 == 0 {
                logLine("[\(tag)] latido de la moto #\(heartbeatsSeen) -> 0x70000001")
            }
            try PxcFrame(PxcFrame.heartbeatAck).write(to: sock)

        case PxcFrame.heartbeatAck, PxcFrame.checkSnResult + 1:
            break

        case PxcFrame.huTimeSync:
            timeSyncSeen += 1
            if timeSyncSeen <= 2 || timeSyncSeen % 30 == 0 {
                logLine("[\(tag)] HU_TIME_SYNC #\(timeSyncSeen) len=\(frame.payload.count) -> 0x10601")
            }
            try PxcFrame(frame.cmd + 1, HuTimeSync.ack(for: frame.payload)).write(to: sock)

        default:
            // Regla general del protocolo: respuesta = cmd+1 vacía. Las pantallas nuevas no
            // abren los puertos de vídeo hasta que se les confirma cada aviso.
            let text = String(frame.payload.asText.prefix(300))
            logLine("[\(tag)] ctrl \(hex(frame.cmd)) len=\(frame.payload.count) \(text) -> \(hex(frame.cmd + 1)) (vacío)")
            try PxcFrame(frame.cmd + 1).write(to: sock)
        }
    }

    private func onClientInfo(_ tag: String, _ frame: PxcFrame, _ sock: TcpSocket) throws {
        let text = frame.payload.asText
        logLine("[\(tag)] *** CLIENT_INFO de la moto *** \(text)")
        var info: [String: Any] = [:]
        if let parsed = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] {
            info = parsed
        } else {
            logLine("[\(tag)] aviso: CLIENT_INFO no es JSON válido; se responde igualmente")
        }
        let huid = (info["HUID"] as? String) ?? (info["huid"] as? String) ?? ""
        let sdk = (info["sdkVersion"] as? String) ?? ""
        logLine("[\(tag)] HUID=\(huid) HUName=\(info["HUName"] as? String ?? "") sdk=\(sdk) channel=\(info["channel"] ?? "")")

        let supportFunction = (huid.hasPrefix("CRCP") || sdk.hasPrefix("0.9.23") || sdk.hasPrefix("1.")) ? 128 : 0
        let signed = huid.isEmpty ? "" : RsaKeys.shared.signHuid(huid)
        if !huid.isEmpty && signed.isEmpty {
            logLine("[\(tag)] !! no se pudo firmar el HUID con RSA")
        }

        // Mismas claves y mismo orden que la respuesta de la app de Android.
        let fields: [(String, String)] = [
            ("pxcVersion", quoted("1.0.2")),
            ("phoneUUID", quoted(phoneUuid)),
            ("phoneBrand", quoted("samsung")),
            ("phoneModel", quoted("SM-G991B")),
            ("phoneOsVersion", quoted("35")),
            ("phoneOs", quoted("Android")),
            ("package", quoted(BikeLink.spoofedPackage)),
            ("versionCode", "126"),
            ("token", "0"),
            ("pubkey", quoted(RsaKeys.shared.publicKeyBase64)),
            ("encryptedHUID", quoted(signed)),
            ("bluetoothName", quoted("OpenCfMoto")),
            ("supportH264IFrame", "true"),
            ("supportFunction", String(supportFunction)),
            ("supportSyncCorrectTime", "false"),
            ("appVersionFingerPrint", quoted("opencfmoto-poc")),
        ]
        let json = "{" + fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
        logLine("[\(tag)] -> respuesta CLIENT_INFO (0x10011) \(json.prefix(160))…")
        try PxcFrame(PxcFrame.clientInfoReply, text: json).write(to: sock)
        status("Saludo en curso…")
    }

    private func onCheckSn(_ tag: String, _ frame: PxcFrame, _ sock: TcpSocket) throws {
        let text = frame.payload.asText
        logLine("[\(tag)] CHECK_SN de la moto: \(text)")
        var sn = ""
        if let parsed = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] {
            sn = (parsed["sn"] as? String) ?? ""
        }
        try PxcFrame(frame.cmd + 1).write(to: sock)
        let result = "{\"isOk\":true,\"errCode\":0,\"errMsg\":\"\",\"id\":\(quoted(sn)),\"client_set\":\"easy_conn\"}"
        logLine("[\(tag)] -> CHECK_SN_RESULT \(result)")
        try PxcFrame(PxcFrame.checkSnResult, text: result).write(to: sock)
    }

    /// Algunas pantallas no envían latidos propios y cortan todo a los ~7 s de silencio,
    /// así que el teléfono envía 0x70000000 cada 2 s por cada conexión de control.
    private func startHeartbeat(_ sock: TcpSocket, _ label: String, _ gen: Int) {
        Thread.detachNewThread { [weak self] in
            var beats = 0
            while let self = self, self.alive(gen), !sock.isClosed {
                Thread.sleep(forTimeInterval: 2.0)
                if !self.alive(gen) || sock.isClosed { break }
                do {
                    try PxcFrame(PxcFrame.heartbeat).write(to: sock)
                    beats += 1
                    if beats <= 2 || beats % 30 == 0 {
                        logLine("[latido] -> \(label) #\(beats)")
                    }
                } catch {
                    logLine("[latido] \(label): no se pudo enviar (\(error))")
                    break
                }
            }
        }
    }

    private func quoted(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "/": out += "\\/"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "\""
    }

    // MARK: - Plano de vídeo (10921 control, 10920 datos)

    private func sendReq(_ sock: TcpSocket, _ cmdType: Int, _ body: Data = Data()) throws {
        var d = Data(capacity: 8 + body.count)
        d.appendLE16(UInt16(truncatingIfNeeded: cmdType))
        d.appendLE16(UInt16(truncatingIfNeeded: body.count))
        d.appendLE32(0)
        d.append(body)
        try sock.writeAll(d)
    }

    private func handleMedia(_ tag: String, _ cmdType: Int, _ body: Data, _ sock: TcpSocket) throws {
        switch cmdType {
        case 16: // REQ_RV_CONFIG_CAPTURE
            let w = body.count >= 2 ? Int(body.le16(0)) : 0
            let h = body.count >= 4 ? Int(body.le16(2)) : 0
            let fps = body.count >= 8 ? Int(body.le32(4)) : 0
            let wantEncoder = body.count >= 12 ? body.le32(8) : 2
            let ext: UInt8 = body.count >= 30 ? body[body.startIndex + 29] : 0
            logLine("[\(tag)] *** CONFIG_CAPTURE: la moto pide \(w)x\(h) fps=\(fps) encoder=\(wantEncoder) ext=\(ext) len=\(body.count) ***")
            if w >= 16 && h >= 16 {
                negW = w & 0xFFF0
                negH = h & 0xFFF0
            }
            var reply = Data()
            reply.appendLE32(wantEncoder == 0 ? 2 : wantEncoder)
            reply.appendLE16(UInt16(negW))
            reply.appendLE16(UInt16(negH))
            reply.append(ext)
            logLine("[\(tag)] -> respuesta 17: \(negW)x\(negH)")
            try sendReq(sock, 17, reply)

        case 48: // REQ_GET_VERSION
            logLine("[\(tag)] GET_VERSION -> 49")
            var v = Data()
            v.appendLE32(3)
            v.appendLE32(1)
            try sendReq(sock, 49, v)

        case 64: // REQ_HEARTBEAT
            try sendReq(sock, 65)

        case 96: // REQ_CONFIGCAPTUREREXTEND
            logLine("[\(tag)] CONFIG_EXTEND len=\(body.count) \(body.asText.prefix(160)) -> 97")
            try sendReq(sock, 97, Data("{\"state\":0}".utf8))

        case 128: // REQ_START_H264
            logLine("[\(tag)] START_H264 len=\(body.count) -> 129")
            try sendReq(sock, 129)

        case 112: // REQ_RV_DATA_START
            logLine("[\(tag)] *** DATA_START: la moto quiere vídeo \(negW)x\(negH) ***")
            startVideo()
            try sendReq(sock, 113)

        case 114: // REQ_RV_DATA_NEXT: un fotograma, en crudo: [tamaño i32 LE][H.264 Annex-B]
            if encoder == nil { startVideo() }
            guard let frame = encoder?.nextFrame(timeoutMs: 1500) else {
                logLine("[\(tag)] DATA_NEXT: no hay fotograma listo")
                return
            }
            var d = Data(capacity: 4 + frame.count)
            d.appendLE32(UInt32(frame.count))
            d.append(frame)
            try sock.writeAll(d)
            framesSent += 1
            if framesSent == 1 {
                logLine("[\(tag)] *** PRIMER FOTOGRAMA ENVIADO: mira la pantalla de la moto ***")
                status("Enviando vídeo a la moto ✓")
            }
            if framesSent <= 5 || framesSent % 100 == 0 {
                logLine("[\(tag)] fotograma #\(framesSent) enviado (\(frame.count) bytes)")
            }

        case 32: // toque en la pantalla (solo en pantallas táctiles)
            touchSeen += 1
            if touchSeen <= 5 || touchSeen % 50 == 0 {
                logLine("[\(tag)] toque #\(touchSeen) \(body.hexPrefix(18))")
            }

        default:
            logLine("[\(tag)] cmd de vídeo desconocido \(cmdType) len=\(body.count) \(body.hexPrefix(32))")
        }
    }

    private func startVideo() {
        lock.lock()
        defer { lock.unlock() }
        if !running { return }
        if let e = encoder, e.width == negW, e.height == negH {
            e.restartStream()
            return
        }
        pattern?.stop()
        encoder?.stop()
        pattern = nil
        encoder = nil

        let fps = 20
        guard let enc = H264Encoder(width: negW, height: negH, fps: fps, bitrate: 2_500_000) else {
            logLine("!! no se pudo iniciar el codificador de vídeo")
            return
        }
        let pat = TestPattern(width: negW, height: negH, fps: fps) { [weak enc] buffer in
            enc?.encode(buffer)
        }
        encoder = enc
        pattern = pat
        enc.restartStream()
        pat.start()
        logLine("[VIDEO] imagen de prueba iniciada \(negW)x\(negH)")
    }

    // MARK: - Estado periódico

    private func statusLoop(_ gen: Int) {
        var i = 0
        while alive(gen) {
            Thread.sleep(forTimeInterval: 5.0)
            if !alive(gen) { break }
            i += 1
            lock.lock()
            let n = clients.count
            lock.unlock()
            logLine("estado #\(i): aceptado=\(probed) conexiones=\(n) fotogramas=\(framesSent)")
        }
    }
}
