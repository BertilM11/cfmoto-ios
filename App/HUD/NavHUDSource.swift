// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreGraphics
import CoreVideo

/// Último estado de la navegación, listo para dibujar. La guía lo escribe desde el hilo
/// principal y el dibujo para la moto lo lee desde su propio hilo.
final class HUDState {
    static let shared = HUDState()

    private let lock = NSLock()
    private var snapshot = HUDSnapshot()

    func set(_ s: HUDSnapshot) {
        lock.lock()
        snapshot = s
        lock.unlock()
    }

    func get() -> HUDSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

/// Origen de imagen para la moto: dibuja la navegación de CFMoto Link a ritmo fijo.
/// Es independiente de lo que muestre la pantalla del iPhone.
final class NavHUDSource: FrameSource {
    static let framesPerSecond = 10

    private let width: Int
    private let height: Int
    private let fps: Int
    private let sink: (CVPixelBuffer) -> Void
    private let queue = DispatchQueue(label: "cfmotolink.hud")
    private var timer: DispatchSourceTimer?
    private let renderer: HUDRenderer
    private var pool: CVPixelBufferPool?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var frames = 0

    init(width: Int, height: Int, fps: Int, sink: @escaping (CVPixelBuffer) -> Void) {
        self.width = width
        self.height = height
        self.fps = max(1, min(fps, NavHUDSource.framesPerSecond))
        self.sink = sink
        renderer = HUDRenderer(width: width, height: height)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(1000 / fps))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        logLine("[MOTO] dibujando la navegación a \(width)x\(height) @\(fps)fps")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let pool = pool else { return }
        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &created)
        guard let buffer = created else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) {
            // Origen arriba a la izquierda, como espera el dibujo.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            renderer.draw(HUDState.shared.get(), now: Date(), in: ctx)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        frames += 1
        sink(buffer)
    }
}
