// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

@main
struct CFMotoLinkApp: App {
    init() {
        // La app está en español: así Apple Maps entrega las indicaciones en español aunque
        // el iPhone esté en otro idioma (la voz también es en español).
        UserDefaults.standard.set(["es-MX", "es"], forKey: "AppleLanguages")
        if UserDefaults.standard.object(forKey: "franjaMoto") as? Bool == false {
            HUDRenderer.reservedBottom = 0
        }
        AppRuntime.install()
    }

    var body: some Scene {
        WindowGroup {
            RootTabs()
        }
    }
}

extension Notification.Name {
    static let cfmAppBecameActive = Notification.Name("cfmAppBecameActive")
}

/// Estado de la app (al frente, en segundo plano, bloqueado) para el registro de diagnóstico.
/// Es lo que permite saber qué pasó con el vídeo a la moto mientras el iPhone estaba bloqueado.
enum AppRuntime {
    private static let lock = NSLock()
    private static var foreground = true
    private static var locked = false
    private static var installed = false

    static var description: String {
        lock.lock()
        defer { lock.unlock() }
        let base = foreground ? "al frente" : "segundo plano"
        return locked ? base + "+bloqueado" : base
    }

    private static func update(foreground f: Bool? = nil, locked l: Bool? = nil) {
        lock.lock()
        if let f = f { foreground = f }
        if let l = l { locked = l }
        lock.unlock()
    }

    static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            update(foreground: false)
            logLine("[APP] pasa a segundo plano")
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            update(foreground: true)
            logLine("[APP] vuelve al frente")
            center.post(name: .cfmAppBecameActive, object: nil)
        }
        center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
            update(locked: true)
            logLine("[APP] iPhone bloqueado")
        }
        center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            update(locked: false)
            logLine("[APP] iPhone desbloqueado")
        }
    }
}
