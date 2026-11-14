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
final class H264Encoder {
    let width: Int
    let height: Int
    let fps: Int

    private var session: VTCompressionSession?
    private let queue = FrameQueue(capacity: 8)
    private let lock = NSLock()
    private var awaitKeyframe = true
    private var forceKeyframe = true
    private var frameIndex: Int64 = 0
    private(set) var encodedFrames = 0

    init?(width: Int, height: Int, fps: Int, bitrate: Int) {
        self.width = width
        self.height = height
        self.fps = fps

        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &s
        )
        guard status == noErr, let created = s else {
            logLine("[VIDEO] no se pudo crear el codificador (status \(status))")
            return nil
        }
        session = created

        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_3_1)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1))
        VTCompressionSessionPrepareToEncodeFrames(created)
        logLine("[VIDEO] codificador H.264 listo \(width)x\(height) @\(fps)fps \(bitrate / 1000)kbps")
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

    func encode(_ pixelBuffer: CVPixelBuffer) {
        guard let s = session else { return }
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
            guard status == noErr, let sample = sample else { return }
            self?.handle(sample)
        }
        if status != noErr {
            logLine("[VIDEO] error al codificar (status \(status))")
        }
    }

    func nextFrame(timeoutMs: Int) -> Data? {
        return queue.pop(timeoutMs: timeoutMs)
    }

    func stop() {
        if let s = session {
            VTCompressionSessionInvalidate(s)
        }
        session = nil
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

        encodedFrames += 1
        if !queue.push(out) {
            // La moto va más lenta que el codificador: tirar lo acumulado y recomenzar en un
            // fotograma clave, para no enviarle nunca fotogramas con referencias perdidas.
            restartStream()
        }
    }
}
