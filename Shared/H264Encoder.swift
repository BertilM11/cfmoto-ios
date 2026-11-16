// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

/// Cola pequeña de fotogramas codificados. La moto los pide de uno en uno.
final class FrameQueue {
    private let cond = NSCondition()
    private var items: [Data] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Devuelve false si la cola estaba llena (el fotograma no se añade).
    func push(_ d: Data) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        if items.count >= capacity { return false }
        items.append(d)
        cond.signal()
        return true
    }

    func pop(timeoutMs: Int) -> Data? {
        cond.lock()
        defer { cond.unlock() }
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while items.isEmpty {
            if !cond.wait(until: deadline) { break }
        }
        if items.isEmpty { return nil }
        return items.removeFirst()
    }

    func clear() {
        cond.lock()
        items.removeAll()
        cond.unlock()
    }
}

/// Codificador H.264 Baseline 3.1 con salida Annex-B (SPS/PPS delante de cada fotograma clave),
/// que es lo que acepta el decodificador de la pantalla.
///
/// iOS invalida la sesión de VideoToolbox cuando la app cambia entre primer y segundo plano.
/// Por eso, ante cualquier fallo, la sesión se vuelve a crear sola (alternando el codificador
/// por hardware y el de software) y el flujo se reanuda en un fotograma clave.
final class H264Encoder {
    let width: Int
    let height: Int
    let fps: Int
    private let bitrate: Int

    private let sessionLock = NSLock()
    private var session: VTCompressionSession?
    private var usingSoftware = false
    private var recreateCount = 0
    private var lastRecreate = Date.distantPast

    private let queue = FrameQueue(capacity: 8)
    private let lock = NSLock()
    private var awaitKeyframe = true
    private var forceKeyframe = true
    private var frameIndex: Int64 = 0
    private var encodedCount = 0
    private var failureCount = 0
    private var keyframe: Data?

    var encodedFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return encodedCount
    }

    var errorCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return failureCount
    }

    /// Último fotograma clave completo. Sirve para repetirlo si el codificador se queda sin salida.
    var lastKeyframe: Data? {
        lock.lock()
        defer { lock.unlock() }
        return keyframe
    }

    var backend: String {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if session == nil { return "ninguno" }
        return usingSoftware ? "software" : "hardware"
    }

    init?(width: Int, height: Int, fps: Int, bitrate: Int) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        if !(openSession(software: false, quiet: false) || openSession(software: true, quiet: false)) {
            logLine("[VIDEO] no se pudo crear ningún codificador H.264")
            return nil
        }
    }

    private func openSession(software: Bool, quiet: Bool) -> Bool {
        var spec: CFDictionary?
        if software {
            spec = [
                "EnableHardwareAcceleratedVideoEncoder": false,
                "RequireHardwareAcceleratedVideoEncoder": false,
            ] as CFDictionary
        }
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &created
        )
        guard status == noErr, let s = created else {
            if !quiet {
                logLine("[VIDEO] no se pudo crear el codificador \(software ? "por software" : "por hardware") (status \(status))")
            }
            return false
        }

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_3_1)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps))
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1))
        let prepared = VTCompressionSessionPrepareToEncodeFrames(s)
        if prepared != noErr {
            if !quiet {
                logLine("[VIDEO] el codificador \(software ? "por software" : "por hardware") no arrancó (status \(prepared))")
            }
            VTCompressionSessionInvalidate(s)
            return false
        }

        var value: CFTypeRef?
        VTSessionCopyProperty(s, key: "UsingHardwareAcceleratedVideoEncoder" as CFString, allocator: kCFAllocatorDefault, valueOut: &value)
        let accelerated = (value as? Bool).map { $0 ? "sí" : "no" } ?? "?"

        sessionLock.lock()
        session = s
        usingSoftware = software
        sessionLock.unlock()
        if !quiet {
            logLine("[VIDEO] codificador H.264 listo \(width)x\(height) @\(fps)fps \(bitrate / 1000)kbps · pedido=\(software ? "software" : "hardware") · acelerado=\(accelerated)")
        }
        return true
    }

    /// La moto se acaba de enganchar: vaciar la cola y garantizar que lo primero que reciba
    /// sea un fotograma clave completo (SPS+PPS+IDR).
    func restartStream() {
        lock.lock()
        awaitKeyframe = true
        forceKeyframe = true
        lock.unlock()
        queue.clear()
    }

    /// La app volvió al frente: si se estaba usando el codificador por software, volver al de
    /// hardware, que gasta menos batería.
    func preferHardware() {
        sessionLock.lock()
        let software = usingSoftware
        let old = session
        if software {
            session = nil
            // Que un fallo simultáneo no cree otra sesión a la vez.
            lastRecreate = Date()
        }
        sessionLock.unlock()
        guard software else { return }
        if let old = old { VTCompressionSessionInvalidate(old) }
        _ = openSession(software: false, quiet: false) || openSession(software: true, quiet: false)
        restartStream()
    }

    func encode(_ pixelBuffer: CVPixelBuffer) {
        sessionLock.lock()
        let current = session
        sessionLock.unlock()
        guard let s = current else {
            recover(reason: "sin sesión", status: 0)
            return
        }

        lock.lock()
        let force = forceKeyframe
        forceKeyframe = false
        let index = frameIndex
        frameIndex += 1
        lock.unlock()

        var props: CFDictionary?
        if force {
            props = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
        }
        let pts = CMTime(value: index, timescale: Int32(fps))
        let status = VTCompressionSessionEncodeFrame(
            s,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: CMTime.invalid,
            frameProperties: props,
            infoFlagsOut: nil
        ) { [weak self] status, _, sample in
            guard let self = self else { return }
            if status != noErr {
                self.recover(reason: "salida", status: status)
                return
            }
            if let sample = sample {
                self.handle(sample)
            }
        }
        if status != noErr {
            recover(reason: "entrada", status: status)
        }
    }

    /// Algo falló (lo habitual: la app cambió de primer a segundo plano). Crear otra sesión,
    /// como mucho una vez por segundo.
    private func recover(reason: String, status: OSStatus) {
        lock.lock()
        failureCount += 1
        let failures = failureCount
        lock.unlock()
        if failures <= 6 || failures % 200 == 0 {
            logLine("[VIDEO] fallo del codificador (\(reason), status \(status)) · fallo #\(failures)")
        }

        sessionLock.lock()
        if Date().timeIntervalSince(lastRecreate) < 1.0 {
            sessionLock.unlock()
            return
        }
        lastRecreate = Date()
        recreateCount += 1
        let attempt = recreateCount
        let old = session
        session = nil
        sessionLock.unlock()

        if let old = old { VTCompressionSessionInvalidate(old) }
        let verbose = attempt <= 6 || attempt % 30 == 0
        // Intentos impares: hardware primero. Pares: software primero.
        let softwareFirst = attempt % 2 == 0
        let ok = openSession(software: softwareFirst, quiet: !verbose) || openSession(software: !softwareFirst, quiet: !verbose)
        if verbose {
            logLine("[VIDEO] reinicio del codificador #\(attempt): \(ok ? "hecho" : "sin éxito")")
        }
        if ok { restartStream() }
    }

    func nextFrame(timeoutMs: Int) -> Data? {
        return queue.pop(timeoutMs: timeoutMs)
    }

    func stop() {
        sessionLock.lock()
        let old = session
        session = nil
        // Evita que un fallo tardío vuelva a crear la sesión.
        lastRecreate = Date.distantFuture
        sessionLock.unlock()
        if let old = old {
            VTCompressionSessionInvalidate(old)
        }
        queue.clear()
    }

    private func handle(_ sample: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sample) else { return }

        var isKey = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first,
           let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKey = !notSync
        }

        lock.lock()
        if awaitKeyframe && !isKey {
            lock.unlock()
            return
        }
        if isKey { awaitKeyframe = false }
        lock.unlock()

        let startCode: [UInt8] = [0, 0, 0, 1]
        var out = Data()

        if isKey, let format = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil
            )
            for i in 0..<count {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format, parameterSetIndex: i, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
                )
                if st == noErr, let p = pointer {
                    out.append(contentsOf: startCode)
                    out.append(p, count: size)
                }
            }
        }

        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let total = CMBlockBufferGetDataLength(block)
        if total <= 4 { return }
        var bytes = [UInt8](repeating: 0, count: total)
        let copied = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: total, destination: &bytes)
        if copied != kCMBlockBufferNoErr { return }

        // AVCC (longitud de 4 bytes big-endian por NAL) -> Annex-B (código de inicio 00 00 00 01).
        var offset = 0
        while offset + 4 <= total {
            let nalLength = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            offset += 4
            if nalLength <= 0 || offset + nalLength > total { break }
            out.append(contentsOf: startCode)
            out.append(contentsOf: bytes[offset..<(offset + nalLength)])
            offset += nalLength
        }
        if out.isEmpty { return }

        lock.lock()
        encodedCount += 1
        if isKey { keyframe = out }
        lock.unlock()

        if !queue.push(out) {
            // La moto va más lenta que el codificador: tirar lo acumulado y recomenzar en un
            // fotograma clave, para no enviarle nunca fotogramas con referencias perdidas.
            restartStream()
        }
    }
}
