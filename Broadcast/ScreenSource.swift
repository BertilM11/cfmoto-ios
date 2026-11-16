// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreImage
import CoreVideo
import ImageIO

/// Último fotograma de la pantalla del iPhone que entregó ReplayKit.
final class ScreenFeed {
    static let shared = ScreenFeed()

    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var orientation: CGImagePropertyOrientation = .up
    private(set) var received = 0

    func update(_ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) {
        lock.lock()
        latest = buffer
        self.orientation = orientation
        received += 1
        lock.unlock()
    }

    func current() -> (CVPixelBuffer, CGImagePropertyOrientation)? {
        lock.lock()
        defer { lock.unlock() }
        guard let b = latest else { return nil }
        return (b, orientation)
    }

    func reset() {
        lock.lock()
        latest = nil
        received = 0
        lock.unlock()
    }
}

/// Envía la pantalla del iPhone a la moto a ritmo fijo. La pantalla se escala para caber
/// entera en la de la moto (con bandas negras), girada según la orientación del iPhone.
/// Si la pantalla no cambia, se repite el último fotograma: la moto pide uno tras otro.
final class ScreenSource: FrameSource {
    private let width: Int
    private let height: Int
    private let fps: Int
    private let sink: (CVPixelBuffer) -> Void
    private let queue = DispatchQueue(label: "cfmotolink.screensource")
    private var timer: DispatchSourceTimer?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var pool: CVPixelBufferPool?
    private var lastRaw: CVPixelBuffer?
    private var lastOrientation: CGImagePropertyOrientation = .up
    private var lastOut: CVPixelBuffer?
    private var converted = 0
    private var loggedSize = false

    init(width: Int, height: Int, fps: Int, sink: @escaping (CVPixelBuffer) -> Void) {
        self.width = width
        self.height = height
        self.fps = fps
        self.sink = sink
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
        t.schedule(deadline: .now(), repeating: .milliseconds(1000 / max(1, fps)))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        logLine("[PANTALLA] enviando la pantalla del iPhone a \(width)x\(height) @\(fps)fps")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        if let current = ScreenFeed.shared.current() {
            let (raw, orientation) = current
            if raw !== lastRaw || orientation != lastOrientation || lastOut == nil {
                if let out = render(raw, orientation) {
                    lastRaw = raw
                    lastOrientation = orientation
                    lastOut = out
                    converted += 1
                    if converted == 1 || converted % 600 == 0 {
                        logLine("[PANTALLA] fotograma convertido #\(converted) (orientación \(orientation.rawValue))")
                    }
                }
            }
        } else if lastOut == nil {
            lastOut = blank()
        }
        if let out = lastOut {
            sink(out)
        }
    }

    private func newBuffer() -> CVPixelBuffer? {
        guard let pool = pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out)
        return out
    }

    private func blank() -> CVPixelBuffer? {
        guard let out = newBuffer() else { return nil }
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        context.render(black, to: out, bounds: black.extent, colorSpace: colorSpace)
        return out
    }

    static func ciOrientation(_ o: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch o {
        case .left: return .right
        case .right: return .left
        case .leftMirrored: return .rightMirrored
        case .rightMirrored: return .leftMirrored
        default: return o
        }
    }

    private func render(_ raw: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
        guard let out = newBuffer() else { return nil }
        let W = CGFloat(width)
        let H = CGFloat(height)

        // ReplayKit marca el giro en el sentido contrario al que aplica CIImage: en horizontal
        // la imagen salía al revés (180°). Se intercambian izquierda y derecha.
        var img = CIImage(cvPixelBuffer: raw).oriented(ScreenSource.ciOrientation(orientation))
        let e = img.extent
        if !loggedSize {
            loggedSize = true
            logLine("[PANTALLA] pantalla del iPhone \(Int(e.width))x\(Int(e.height)) -> moto \(width)x\(height)")
        }
        guard e.width > 0, e.height > 0 else { return nil }
        let scale = min(W / e.width, H / e.height)
        img = img
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = ((W - e.width * scale) / 2).rounded()
        let dy = ((H - e.height * scale) / 2).rounded()
        img = img.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        let frame = CGRect(x: 0, y: 0, width: W, height: H)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: frame)
        context.render(img.composited(over: black), to: out, bounds: frame, colorSpace: colorSpace)
        return out
    }
}
