// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import UIKit
import CoreVideo

/// Imagen de prueba animada (barras de color, reloj y contador). Si esto aparece en la pantalla
/// de la moto, el enlace iPhone -> moto funciona de punta a punta.
final class TestPattern {
    private let width: Int
    private let height: Int
    private let fps: Int
    private let sink: (CVPixelBuffer) -> Void
    private let queue = DispatchQueue(label: "cfmotolink.testpattern")
    private var timer: DispatchSourceTimer?
    private var frame = 0

    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(width: Int, height: Int, fps: Int, sink: @escaping (CVPixelBuffer) -> Void) {
        self.width = width
        self.height = height
        self.fps = fps
        self.sink = sink
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(1000 / max(1, fps)))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        frame += 1
        var created: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &created)
        guard let buffer = created else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) {
            // Coordenadas estilo UIKit: origen arriba a la izquierda.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            draw(in: ctx)
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        sink(buffer)
    }

    private func draw(in ctx: CGContext) {
        let w = CGFloat(width)
        let h = CGFloat(height)

        ctx.setFillColor(UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Barras de color arriba: sirven para comprobar que los colores no llegan cambiados.
        let colors: [UIColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue]
        let barWidth = w / CGFloat(colors.count)
        let barHeight = h * 0.16
        for (i, c) in colors.enumerated() {
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: CGFloat(i) * barWidth, y: 0, width: barWidth + 1, height: barHeight))
        }

        // Cuadro que se mueve: demuestra que el vídeo está vivo y no congelado.
        let box = h * 0.07
        let travel = max(1, Int(w - box))
        let x = CGFloat((frame * 6) % travel)
        ctx.setFillColor(UIColor.orange.cgColor)
        ctx.fill(CGRect(x: x, y: h - box - 4, width: box, height: box))

        let titleSize = h * 0.15
        let title = "iPhone conectado a CFMOTO" as NSString
        title.draw(
            at: CGPoint(x: w * 0.04, y: h * 0.22),
            withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: titleSize),
                .foregroundColor: UIColor.white,
            ]
        )

        let time = clock.string(from: Date()) as NSString
        time.draw(
            at: CGPoint(x: w * 0.04, y: h * 0.42),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: h * 0.26, weight: .bold),
                .foregroundColor: UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1),
            ]
        )

        let info = "CFMoto Link · prueba de vídeo · cuadro \(frame)" as NSString
        info.draw(
            at: CGPoint(x: w * 0.04, y: h * 0.74),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: h * 0.075),
                .foregroundColor: UIColor(white: 0.8, alpha: 1),
            ]
        )
    }
}
