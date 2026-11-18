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
        // Solo en la prueba automática: tema del panel según el modo de la prueba y música de
        // ejemplo con una portada dibujada aquí (rojo y negro), para ver los colores dinámicos.
        DashStore.shared.config.theme = mode == "night" ? .dark : .light
        // 0.7: «-mapa apple» prueba el modo Apple Maps; si no, el mapa propio de OpenStreetMap.
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-mapa"), i + 1 < arguments.count {
            DashStore.shared.config.map.provider = arguments[i + 1] == "apple" ? .apple : .osm
        }
        DashState.shared.setMusic(MusicSnapshot(
            available: true, source: "Demo", title: "Canción de demostración", artist: "Prueba automática",
            album: "Álbum de demostración", playing: true, duration: 214, position: 60, positionTime: Date().timeIntervalSinceReferenceDate,
            artwork: DashDemo.artwork, palette: DashDemo.palette
        ))
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
        let now = Date()
        let image = renderer.image { context in
            // UIKit ya entrega el contexto con el origen arriba a la izquierda.
            HUDRenderer(width: width, height: height).drawDashboard(DashState.shared.snapshot(now: now), now: now, in: context.cgContext)
        }
        try? image.pngData()?.write(to: folder.appendingPathComponent("hud.png"))

        // El mismo instante en cada modo, con el mapa de calles real, para revisarlos todos.
        for mode in [DashMode.gps, .gpsMusic, .split, .music, .full] {
            var s = DashState.shared.snapshot(now: now)
            s.layout = DashLayout.preset(mode)
            if s.map == nil && s.layout.showsMap && s.mapSettings.provider == .apple { s.map = TFTMap.shared.base(for: s.nav, now: now) }
            let frame = renderer.image { context in
                HUDRenderer(width: width, height: height).drawDashboard(s, now: now, in: context.cgContext)
            }
            try? frame.pngData()?.write(to: folder.appendingPathComponent("hud-\(mode.rawValue).png"))
        }
    }
}
