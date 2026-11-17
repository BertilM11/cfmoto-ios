// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit
import Combine

/// Configuración del panel (modo, diseño, perfiles, reglas) y avisos. Guarda todo en el
/// iPhone y lo pasa al dibujo para la moto. Hace de gestor de modos y de avisos.
final class DashStore: ObservableObject {
    static let shared = DashStore()
    private static let key = "dash.config.v1"

    @Published var config: DashConfig {
        didSet {
            guard config != oldValue else { return }
            persist()
            if config.musicProvider != oldValue.musicProvider {
                // Al cambiar de proveedor, la moto deja de mostrar la canción del anterior.
                DashState.shared.setMusic(MusicSnapshot())
                logLine("[MÚSICA] proveedor: \(config.musicProvider.title)")
            }
        }
    }
    @Published private(set) var history: [NoticeSnapshot] = []

    private var auto = DashAutoState()
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private var wasNavigating = false
    private var wasRerouting = false
    private var wasNear = false
    private var linkUp = false
    private var lowBatteryTold = false
    private var nextNoticeId = 1
    private let previewRenderer = HUDRenderer(width: 800, height: 400)
    private var previewReserve = HUDRenderer.reservedBottom

    private init() {
        if let data = UserDefaults.standard.data(forKey: DashStore.key), let saved = DashConfig.decoded(data) {
            config = saved
        } else {
            config = DashConfig()
        }
        DashState.shared.apply(config)
    }

    private func persist() {
        if let data = config.encoded() {
            UserDefaults.standard.set(data, forKey: DashStore.key)
        }
        DashState.shared.apply(config)
    }

    // MARK: - Arranque

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in self?.checkBattery() }
            .store(in: &bag)
        checkBattery()

        LinkModel.shared.$status
            .removeDuplicates()
            .sink { [weak self] status in self?.linkStatus(status) }
            .store(in: &bag)

        TFTMap.shared.start()
    }

    // MARK: - Modos y edición

    func setMode(_ mode: DashMode) {
        auto = DashAutoState()
        if mode == .custom && config.mode != .custom {
            config.custom = config.layout
        }
        config.mode = mode
        config.activeProfile = nil
    }

    /// Cualquier cambio manual del diseño pasa el panel a modo personalizado.
    func edit(_ change: (inout DashLayout) -> Void) {
        var c = config
        var layout = c.layout
        change(&layout)
        layout.normalize()
        c.custom = layout
        c.mode = .custom
        c.activeProfile = nil
        auto = DashAutoState()
        config = c
    }

    func apply(_ profile: DashProfile) {
        var c = config
        c.custom = profile.layout.normalized
        c.theme = profile.theme
        c.mode = .custom
        c.activeProfile = profile.id
        auto = DashAutoState()
        config = c
    }

    func saveProfile(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let profile = DashProfile(name: clean, layout: config.layout, theme: config.theme)
        var c = config
        c.profiles.append(profile)
        c.custom = profile.layout
        c.mode = .custom
        c.activeProfile = profile.id
        config = c
    }

    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = config.profiles.firstIndex(where: { $0.id == id }) else { return }
        config.profiles[i].name = clean
    }

    func delete(_ id: UUID) {
        config.profiles.removeAll { $0.id == id }
        if config.activeProfile == id { config.activeProfile = nil }
    }

    /// Vuelve al diseño de fábrica. Se conservan la conexión de música (Client ID de Spotify y
    /// servicio elegido), el proveedor de navegación y los perfiles guardados.
    func restoreDefaults() {
        auto = DashAutoState()
        var c = DashConfig()
        c.spotifyClientID = config.spotifyClientID
        c.musicProvider = config.musicProvider
        c.navProvider = config.navProvider
        c.profiles = config.profiles
        config = c
    }

    // MARK: - Vista previa (el mismo dibujo que recibe la moto)

    func previewImage(demo: Bool, layout: DashLayout? = nil, now: Date = Date()) -> CGImage? {
        var s = demo ? DashDemo.snapshot(layout: config.layout, theme: config.theme, now: now) : DashState.shared.snapshot(now: now)
        if demo {
            s.privacy = config.noticePrivacy
            s.showArtwork = config.showArtwork
            s.showProgress = config.showProgress
            s.mapSettings = config.map
            s.musicStyle = config.musicStyle
            s.musicIntensity = config.musicIntensity
            s.artworkSize = config.artworkSize
            s.showArtist = config.showArtist
            s.showSource = config.showSource
        }
        if let layout = layout { s.layout = layout }
        if previewReserve != HUDRenderer.reservedBottom {
            previewReserve = HUDRenderer.reservedBottom
            return DashPreview.image(s, now: now)
        }
        return DashPreview.image(s, now: now, renderer: previewRenderer)
    }

    // MARK: - Reglas automáticas y avisos

    private func fire(_ event: DashEvent) {
        var c = config
        if DashRulesEngine.apply(event, config: &c, auto: &auto) {
            c.activeProfile = nil
            config = c
            logLine("[PANEL] cambio automático de modo: \(c.mode.title)")
        }
    }

    func musicStarted() {
        fire(.musicStarted(routeActive: HUDState.shared.get().navigating))
    }

    private func poll() {
        let n = HUDState.shared.get()
        if n.navigating != wasNavigating {
            wasNavigating = n.navigating
            if n.navigating {
                fire(.navStarted)
                notify(.nav, "Ruta iniciada", HUDFormat.duration(n.remainingTime) + " hasta el destino")
            } else {
                fire(.navEnded)
                if n.arrived { notify(.nav, "Llegaste", n.destinationName) }
            }
        }
        if n.navigating {
            if n.rerouting && !wasRerouting { notify(.nav, "Recalculando la ruta", "Te saliste del camino") }
            wasRerouting = n.rerouting
            let near = n.distanceToManeuver < 180
            if near != wasNear {
                wasNear = near
                fire(near ? .turnNear : .turnPassed)
            }
        } else if wasNear {
            wasNear = false
            fire(.turnPassed)
        }
    }

    private func checkBattery() {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return }
        if level <= 0.2 && !lowBatteryTold {
            lowBatteryTold = true
            notify(.battery, "Batería del iPhone", "Queda \(Int((level * 100).rounded())) %")
        } else if level > 0.25 {
            lowBatteryTold = false
        }
    }

    private func linkStatus(_ status: String) {
        if status.contains("Enviando") {
            if !linkUp {
                linkUp = true
                notify(.link, "Moto conectada", "Enviando el panel")
            }
        } else if linkUp && (status.hasPrefix("Error") || status.contains("perdido") || status == "Detenido" || status == "Sin conectar") {
            linkUp = false
            notify(.link, "Conexión con la moto", status)
        }
    }

    func notify(_ kind: NoticeKind, _ title: String, _ text: String) {
        switch kind {
        case .nav: if !config.noticeNav { return }
        case .link: if !config.noticeLink { return }
        case .battery: if !config.noticeBattery { return }
        case .test: break
        }
        let n = NoticeSnapshot(id: nextNoticeId, kind: kind, title: title, text: text, time: Date().timeIntervalSinceReferenceDate)
        nextNoticeId += 1
        DashState.shared.post(n)
        history.insert(n, at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
    }
}
