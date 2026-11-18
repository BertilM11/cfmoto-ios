// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Diagnóstico: todo lo que hace falta para saber qué pasa en la moto sin tocar el código
// (enlace, vídeo, GPS, mapa guardado, segundo plano, memoria, red, tema, música, proveedor).
// El informe exportado no lleva contraseñas, permisos de Spotify ni el Client ID, y la posición
// va redondeada (unos 100 m).
import Foundation
import UIKit
import Network
import os

/// Red del iPhone: si hay salida a internet y por dónde. La red de la moto es un Wi-Fi sin
/// internet; el mapa necesita los datos móviles a la vez.
final class NetworkWatch {
    static let shared = NetworkWatch()

    private let main = NWPathMonitor()
    private let cellular = NWPathMonitor(requiredInterfaceType: .cellular)
    private let queue = DispatchQueue(label: "cfmoto.red")
    private let lock = NSLock()
    private var mainText = "sin datos"
    private var cellularOK: Bool?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        main.pathUpdateHandler = { [weak self] path in self?.update(path) }
        cellular.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.lock.lock()
            let before = self.cellularOK
            let now = path.status == .satisfied
            self.cellularOK = now
            self.lock.unlock()
            if before != now { logLine("[RED] datos móviles: \(now ? "disponibles" : "no disponibles")") }
        }
        main.start(queue: queue)
        cellular.start(queue: queue)
    }

    private func update(_ path: NWPath) {
        var parts: [String] = []
        switch path.status {
        case .satisfied: parts.append("con salida")
        case .unsatisfied: parts.append("sin salida")
        case .requiresConnection: parts.append("esperando conexión")
        @unknown default: parts.append("estado desconocido")
        }
        var via: [String] = []
        if path.usesInterfaceType(.cellular) { via.append("datos móviles") }
        if path.usesInterfaceType(.wifi) { via.append("Wi-Fi") }
        if !via.isEmpty { parts.append("por " + via.joined(separator: " y ")) }
        if path.isExpensive { parts.append("costosa") }
        if path.isConstrained { parts.append("modo de datos reducidos") }
        let text = parts.joined(separator: ", ")
        lock.lock()
        let changed = text != mainText
        mainText = text
        lock.unlock()
        if changed { logLine("[RED] \(text)") }
    }

    var description: String {
        lock.lock()
        defer { lock.unlock() }
        var s = mainText
        if let c = cellularOK { s += c ? " · datos móviles disponibles" : " · sin datos móviles" }
        return s
    }
}

enum MemoryInfo {
    /// Memoria que usa la app (la cifra que vigila iOS), en MB.
    static func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Memoria que le queda a la app antes de que iOS la cierre, en MB (nil si no se sabe).
    static func availableMB() -> Double? {
        let a = os_proc_available_memory()
        return a > 0 ? Double(a) / 1_048_576 : nil
    }
}

final class Diagnostics {
    static let shared = Diagnostics()

    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var warn = false
    }

    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }

    private var timer: Timer?
    private var lastFrames = 0
    private var lastFramesTime = Date()
    private(set) var fps: Double = 0
    private var backgroundSince: Date?

    func start() {
        guard timer == nil else { return }
        NetworkWatch.shared.start()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.periodic() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.backgroundSince = Date()
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            if let since = self?.backgroundSince {
                logLine(String(format: "[DIAG] la app estuvo %.0f s en segundo plano", Date().timeIntervalSince(since)))
            }
            self?.backgroundSince = nil
        }
    }

    /// Una línea cada 10 s mientras hay ruta o enlace con la moto: lo necesario para las
    /// pruebas con el iPhone bloqueado (posición, mapa, cobertura, vídeo, memoria, red).
    private func periodic() {
        updateFps()
        let n = HUDState.shared.get()
        guard n.navigating || LinkModel.shared.running else { return }
        logLine("[DIAG] " + compactLine())
    }

    private func updateFps() {
        let s = LinkModel.shared.linkStats()
        let now = Date()
        let dt = now.timeIntervalSince(lastFramesTime)
        guard dt > 0.5 else { return }
        fps = Double(max(0, s.framesSent - lastFrames)) / dt
        lastFrames = s.framesSent
        lastFramesTime = now
    }

    // MARK: - Formato

    static func age(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else { return "—" }
        if s < 90 { return String(format: "hace %.0f s", s) }
        if s < 5400 { return String(format: "hace %.0f min", s / 60) }
        return String(format: "hace %.1f h", s / 3600)
    }

    static func km(_ meters: Double) -> String { String(format: "%.1f km", meters / 1000) }

    // MARK: - Contenido

    private func compactLine() -> String {
        let map = TFTMap.shared.stats()
        let link = LinkModel.shared.linkStats()
        var parts: [String] = []
        parts.append("app=\(AppRuntime.description)")
        if let l = LocationService.shared.last {
            parts.append(String(format: "gps=%.0fs±%.0fm", -l.timestamp.timeIntervalSinceNow, l.horizontalAccuracy))
        } else {
            parts.append("gps=sin fijo")
        }
        parts.append("fijos=\(LocationService.shared.fixes)/\(LocationService.shared.backgroundFixes)bg")
        parts.append("mapa=\(map.source)")
        if let a = map.sourceAge { parts.append(String(format: "edad=%.0fs", a)) }
        if map.routeActive {
            parts.append(String(format: "cobertura=%.1f/%.1fkm", map.coverage.continuous / 1000, map.routeRemaining / 1000))
        }
        parts.append(String(format: "imgs=%d(%.1fMB)", map.cached, Double(map.cachedBytes) / 1_048_576))
        parts.append("pend=\(map.inFlight)")
        parts.append(String(format: "envio=%.1ffps", fps))
        parts.append("cod=\(link.backend)/\(link.encoderFailures)f")
        if let m = MemoryInfo.footprintMB() { parts.append(String(format: "mem=%.0fMB", m)) }
        parts.append("red=\(NetworkWatch.shared.description)")
        parts.append("temp=\(Diagnostics.thermal())")
        let level = UIDevice.current.batteryLevel
        if level >= 0 { parts.append(String(format: "bat=%.0f%%", level * 100)) }
        return parts.joined(separator: " ")
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "normal"
        case .fair: return "tibio"
        case .serious: return "caliente"
        case .critical: return "crítico"
        @unknown default: return "?"
        }
    }

    func sections() -> [Section] {
        updateFps()
        let link = LinkModel.shared.linkStats()
        let map = TFTMap.shared.stats()
        let render = RenderStats.snapshot()
        let config = DashStore.shared.config
        let now = Date().timeIntervalSinceReferenceDate
        var out: [Section] = []

        out.append(Section(title: "Moto (Wi-Fi Direct y protocolo)", rows: [
            Row(label: "Estado", value: LinkModel.shared.status),
            Row(label: "Enlace de la app", value: link.running ? "activo" : "parado"),
            Row(label: "Aviso aceptado por la moto", value: link.accepted ? "sí" : "no", warn: link.running && !link.accepted),
            Row(label: "Conexiones abiertas", value: "\(link.connections)", warn: link.running && link.connections == 0),
            Row(label: "Reintentos de reconexión", value: "\(link.reconnectAttempts)", warn: link.reconnectAttempts > 0),
            Row(label: "Wi-Fi del iPhone", value: wifiText()),
        ]))

        out.append(Section(title: "Vídeo a la moto", rows: [
            Row(label: "Fotogramas enviados", value: "\(link.framesSent) (repetidos \(link.framesRepeated))"),
            Row(label: "Ritmo de envío", value: String(format: "%.1f por segundo", fps), warn: link.running && fps < 1),
            Row(label: "Último fotograma", value: Diagnostics.age(link.lastFrameAge), warn: (link.lastFrameAge ?? 0) > 5),
            Row(label: "Codificador H.264", value: "\(link.backend) · \(link.encoded) codificados · \(link.encoderFailures) fallos", warn: link.encoderFailures > 0),
            Row(label: "Tamaño pedido por la moto", value: link.size),
            Row(label: "Dibujo del panel", value: String(format: "%.1f ms por imagen · %d imágenes", render.averageMs, render.frames)),
            Row(label: "Último dibujo", value: Diagnostics.age(render.last > 0 ? now - render.last : nil)),
        ]))

        var gpsRows: [Row] = []
        if let l = LocationService.shared.last {
            let ageSeconds = -l.timestamp.timeIntervalSinceNow
            gpsRows.append(Row(label: "Posición", value: String(format: "%.5f, %.5f (±%.0f m)", l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy)))
            gpsRows.append(Row(label: "Edad de la posición", value: Diagnostics.age(ageSeconds), warn: ageSeconds > 10))
            gpsRows.append(Row(label: "Velocidad", value: l.speed >= 0 ? String(format: "%.0f km/h", l.speed * 3.6) : "—"))
        } else {
            gpsRows.append(Row(label: "Posición", value: "sin fijo", warn: true))
        }
        gpsRows.append(Row(label: "Fijos recibidos", value: "\(LocationService.shared.fixes) (con la app en segundo plano: \(LocationService.shared.backgroundFixes))"))
        out.append(Section(title: "GPS", rows: gpsRows))

        let continuous = map.coverage.continuous
        let enough = continuous >= min(map.routeRemaining, 5000) - 1
        var mapRows: [Row] = [
            Row(label: "Imagen en la moto", value: map.source, warn: map.source == MapSource.none.rawValue),
            Row(label: "Edad de esa imagen", value: Diagnostics.age(map.sourceAge)),
            Row(label: "Última imagen en vivo", value: Diagnostics.age(map.liveAge)),
            Row(label: "Imágenes guardadas", value: String(format: "%d (%.1f MB de %.0f MB permitidos; caben %d)", map.cached, Double(map.cachedBytes) / 1_048_576, Double(map.budgetBytes) / 1_048_576, map.capacity)),
            Row(label: "Guardadas con el otro tema", value: "\(map.cachedOtherStyle)"),
            Row(label: "Peticiones", value: "\(map.requests) · llegaron \(map.successes) · fallaron \(map.failures) · pendientes \(map.inFlight)", warn: map.failures > 0),
            Row(label: "Llegaron tarde (tras segundo plano)", value: "\(map.late) · descartadas \(map.discardedLate) · canceladas por espera \(map.watchdog)"),
        ]
        if map.routeActive {
            mapRows.append(Row(label: "Mapa seguido por delante", value: Diagnostics.km(continuous) + " de " + Diagnostics.km(map.routeRemaining), warn: !enough))
            mapRows.append(Row(label: "Con imagen en total", value: Diagnostics.km(map.coverage.covered) + " · tramos sin imagen: \(map.coverage.gaps)"))
            mapRows.append(Row(label: "Imágenes extra para curvas", value: "\(map.gapFills)"))
            mapRows.append(Row(label: "Objetivo de guardado", value: Diagnostics.km(map.target) + String(format: " · una imagen cada %.0f m y en cada giro", map.step)))
        }
        if !map.lastError.isEmpty { mapRows.append(Row(label: "Último error", value: map.lastError, warn: true)) }
        out.append(Section(title: "Mapa de calles", rows: mapRows))

        var appRows: [Row] = [
            Row(label: "Estado", value: AppRuntime.description),
            Row(label: "Segundo plano desde", value: backgroundSince.map { Diagnostics.age(Date().timeIntervalSince($0)) } ?? "—"),
            Row(label: "Temperatura del iPhone", value: Diagnostics.thermal(), warn: ProcessInfo.processInfo.thermalState.rawValue >= 2),
            Row(label: "Batería", value: batteryText()),
            Row(label: "Red", value: NetworkWatch.shared.description),
        ]
        if let m = MemoryInfo.footprintMB() {
            let free = MemoryInfo.availableMB().map { String(format: " · libre %.0f MB", $0) } ?? ""
            appRows.append(Row(label: "Memoria", value: String(format: "%.0f MB en uso", m) + free))
        }
        out.append(Section(title: "iPhone", rows: appRows))

        let night = DashState.shared.isNight(.night)
        out.append(Section(title: "Tema, música y navegación", rows: [
            Row(label: "Tema elegido", value: config.theme.title),
            Row(label: "Tema que se aplica ahora", value: night ? "oscuro (noche)" : "claro (día)"),
            Row(label: "Tema de la moto", value: DashState.shared.themeFollowsMap ? "el del mapa guardado (hasta tener imágenes del tema elegido)" : "el que se aplica ahora"),
            Row(label: "Estilo del mapa pedido", value: map.wantedStyle.isEmpty ? "—" : map.wantedStyle),
            Row(label: "Servicio de música", value: config.musicProvider.title),
            Row(label: "Spotify", value: SpotifyService.shared.statusText),
            Row(label: "Proveedor de navegación", value: config.navProvider.title),
            Row(label: "Guía en otra app", value: RouteManager.shared.external.map { "\($0.provider.title) → \($0.name)" } ?? "no"),
            Row(label: "Ruta en CFMoto Link", value: NavEngine.shared.phase == .navigating ? "guiando" : "sin guía"),
        ]))

        let errors = Diagnostics.recentErrors()
        out.append(Section(title: "Errores recientes", rows: errors.isEmpty
            ? [Row(label: "—", value: "ninguno en el registro")]
            : errors.map { Row(label: "", value: $0, warn: true) }))
        return out
    }

    private func wifiText() -> String {
        let interfaces = wifiInterfaces()
        guard !interfaces.isEmpty else { return "sin Wi-Fi con IP" }
        return interfaces.map { "\($0.iface) \($0.ip)" }.joined(separator: ", ")
    }

    private func batteryText() -> String {
        let device = UIDevice.current
        let level = device.batteryLevel
        guard level >= 0 else { return "—" }
        let state: String
        switch device.batteryState {
        case .charging: state = "cargando"
        case .full: state = "llena"
        case .unplugged: state = "sin cargar"
        default: state = "?"
        }
        return String(format: "%.0f %% · %@", level * 100, state)
    }

    static func recentErrors() -> [String] {
        let keys = ["error", "fallo", "no se pudo", "no llegó", "!!", "sin éxito", "perdido", "descartad"]
        return LogBus.shared.recent(800)
            .filter { line in
                let l = line.lowercased()
                return keys.contains { l.contains($0) }
            }
            .suffix(15)
            .map { $0 }
    }

    /// Informe para enviar: secciones, errores y el final del registro. Sin credenciales; la
    /// posición se redondea a 3 decimales (unos 100 m).
    func report() -> String {
        var lines: [String] = []
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_GT")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("CFMoto Link \(version) (\(build)) · informe de diagnóstico · \(f.string(from: Date()))")
        lines.append("iPhone: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)")
        lines.append("")
        for section in sections() {
            lines.append("== \(section.title) ==")
            for row in section.rows {
                var value = row.value
                if row.label == "Posición" { value = Diagnostics.roundedPosition() ?? value }
                lines.append((row.label.isEmpty ? "" : row.label + ": ") + value + (row.warn ? "  ⚠︎" : ""))
            }
            lines.append("")
        }
        lines.append("== Registro (últimas 300 líneas) ==")
        lines.append(contentsOf: LogBus.shared.recent(300).map(Diagnostics.redact))
        return lines.joined(separator: "\n")
    }

    private static func roundedPosition() -> String? {
        guard let l = LocationService.shared.last else { return nil }
        return String(format: "%.3f, %.3f (redondeada, ±%.0f m)", l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy)
    }

    /// Por si acaso: nada que parezca un permiso o una clave sale en el informe.
    static func redact(_ line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("token") || lower.contains("client id") || lower.contains("clientid") || lower.contains("contraseña") || lower.contains("password") {
            return "[línea omitida por privacidad]"
        }
        return line
    }
}
