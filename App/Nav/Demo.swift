// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import UIKit
import CoreLocation

/// Modo de demostración para la compilación automática: la app se lanza en el simulador con
/// "-demo <modo>", recorre una ruta de ejemplo y deja en Documentos el registro y la imagen
/// que se enviaría a la moto, para poder revisar el resultado sin un iPhone delante.
/// No se activa nunca en un uso normal.
enum Demo {
    static let mode: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-demo"), i + 1 < arguments.count {
            return arguments[i + 1]
        }
        return nil
    }()

    /// Terminal del Aeropuerto La Aurora, Ciudad de Guatemala.
    static let destination = CLLocationCoordinate2D(latitude: 14.5880, longitude: -90.5302)

    private static var dumpTimer: Timer?

    /// Espera a que se cumpla una condición (hasta 40 s) y entonces ejecuta la acción.
    static func when(_ condition: @escaping () -> Bool, _ action: @escaping () -> Void) {
        var tries = 0
        func check() {
            if condition() {
                action()
                return
            }
            tries += 1
            if tries < 130 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: check)
            }
        }
        check()
    }

    static func startDumping() {
        guard dumpTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { _ in dump() }
        RunLoop.main.add(timer, forMode: .common)
        dumpTimer = timer
    }

    private static func dump() {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? LogBus.shared.text.write(to: folder.appendingPathComponent("demo-log.txt"), atomically: true, encoding: .utf8)

        let width = 800
        let height = 400
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return format
        }())
        let image = renderer.image { context in
            // UIKit ya entrega el contexto con el origen arriba a la izquierda.
            HUDRenderer(width: width, height: height).draw(HUDState.shared.get(), now: Date(), in: context.cgContext)
        }
        try? image.pngData()?.write(to: folder.appendingPathComponent("hud.png"))
    }
}
