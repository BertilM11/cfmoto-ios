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
        Self.styleBars()
    }

    /// Barras oscuras en toda la app, sin depender de si el iPhone está en modo claro u oscuro.
    private static func styleBars() {
        let bg = UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        let dim = UIColor(red: 0.6, green: 0.65, blue: 0.73, alpha: 1)
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bg
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(red: 0.035, green: 0.05, blue: 0.08, alpha: 1)
        tabs.shadowColor = .clear
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = dim
            item.normal.titleTextAttributes = [.foregroundColor: dim]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().unselectedItemTintColor = dim
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
