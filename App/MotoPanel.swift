// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit
import ReplayKit

/// Estado del enlace con la moto. Hay dos formas de enviar imagen:
///  - Navegación de CFMoto Link: la app dibuja su propia pantalla (flecha, distancia, minimapa).
///  - Duplicar pantalla: la extensión de transmisión copia lo que se ve en el iPhone.
final class LinkModel: ObservableObject {
    @Published var running = false
    @Published var status = "Sin conectar"
    @Published var manualIp = ""
    @Published var copied = false
    /// Registro de la extensión de transmisión (vacío si no está activa).
    @Published var broadcastLog: [String] = []
    @Published var broadcasting = false

    /// Hay imagen saliendo hacia la moto por cualquiera de las dos vías.
    var linked: Bool { running || broadcasting }

    private let link = BikeLink()
    private var pollTimer: Timer?
    private var observer: NSObjectProtocol?

    init() {
        link.role = "navegación"
        link.sourceFactory = { width, height, fps, sink in
            NavHUDSource(width: width, height: height, fps: fps, sink: sink)
        }
        link.stateProvider = { AppRuntime.description }
        link.onStatus = { [weak self] s in
            DispatchQueue.main.async { self?.status = s }
        }
        observer = NotificationCenter.default.addObserver(forName: .cfmAppBecameActive, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.running else { return }
            let link = self.link
            DispatchQueue.global(qos: .userInitiated).async { link.appBecameActive() }
        }
        startPolling()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Empieza a enviar la navegación de CFMoto Link a la moto.
    func connect() {
        guard !running else { return }
        running = true
        status = "Iniciando…"
        NavEngine.shared.linkActive = true
        let ip = manualIp
        let link = self.link
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let started = link.start(manualBikeIp: ip)
            if !started {
                DispatchQueue.main.async {
                    self?.running = false
                    NavEngine.shared.linkActive = false
                }
            }
        }
    }

    func disconnect() {
        guard running else { return }
        running = false
        NavEngine.shared.linkActive = false
        let link = self.link
        DispatchQueue.global(qos: .userInitiated).async {
            link.stop()
        }
    }

    /// Antes de duplicar la pantalla hay que soltar los puertos que usa el enlace de la app.
    func prepareForBroadcast() {
        if running {
            logLine("se detiene el envío de la navegación para dejar los puertos libres al duplicado de pantalla")
            running = false
            NavEngine.shared.linkActive = false
            link.stop()
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let text = LogShare.fetch()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let t = text {
                        if !self.broadcasting { self.broadcasting = true }
                        self.broadcastLog = t.isEmpty ? [] : t.components(separatedBy: "\n")
                    } else if self.broadcasting {
                        self.broadcasting = false
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func copyLog() {
        var text = LogBus.shared.text
        if !broadcastLog.isEmpty {
            text += "\n\n==== Registro del duplicado de pantalla ====\n" + broadcastLog.joined(separator: "\n")
        }
        UIPasteboard.general.string = text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.copied = false
        }
    }
}

/// Selector del sistema para iniciar o detener la transmisión de pantalla, limitado a nuestra
/// extensión. Se dibuja oculto y lo activa nuestro propio botón.
final class BroadcastPicker {
    static let shared = BroadcastPicker()
    let view: RPSystemBroadcastPickerView

    private init() {
        view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        view.showsMicrophoneButton = false
        view.preferredExtension = BroadcastPicker.extensionBundleId()
    }

    /// El identificador real de la extensión (Sideloadly puede cambiarlo al firmar).
    static func extensionBundleId() -> String? {
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for item in items where item.pathExtension == "appex" {
            if let id = Bundle(url: item)?.bundleIdentifier {
                return id
            }
        }
        return nil
    }

    func open() {
        for case let button as UIButton in view.subviews {
            button.sendActions(for: .touchUpInside)
            return
        }
        logLine("!! no se encontró el botón del selector de transmisión; usa el Centro de control")
    }
}

struct PickerHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        host.alpha = 0.02
        host.addSubview(BroadcastPicker.shared.view)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Panel "Moto": conectar, duplicar pantalla y ver el registro.
struct MotoPanel: View {
    @ObservedObject var model: LinkModel
    @ObservedObject private var logBus = LogBus.shared

    private var shownLines: [String] {
        if model.broadcasting && !model.running {
            return model.broadcastLog
        }
        return logBus.lines
    }

    private var statusText: String {
        if model.broadcasting && !model.running { return "Duplicando la pantalla" }
        return model.status
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Pantalla de la moto")
                        .font(.title2.bold())
                    Spacer()
                    Circle()
                        .fill(model.linked ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. En la moto, abre la pantalla del código QR y déjala abierta.")
                    Text("2. En Ajustes > Wi-Fi, conéctate a DIRECT-…-CFMOTO (clave 12345678).")
                    Text("3. Elige abajo qué enviar.")
                }
                .font(.footnote)
                .foregroundColor(.secondary)

                // Navegación propia
                VStack(alignment: .leading, spacing: 8) {
                    Text("Navegación de CFMoto Link")
                        .font(.headline)
                    Text("Envía una pantalla hecha para la moto: flecha, distancia, calle y minimapa. No depende de lo que muestre el iPhone.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button {
                        if model.running {
                            model.disconnect()
                        } else {
                            model.connect()
                        }
                    } label: {
                        Label(
                            model.running ? "Detener" : "Enviar navegación a la moto",
                            systemImage: model.running ? "stop.fill" : "location.north.line.fill"
                        )
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.running ? .red : .blue)
                    .disabled(model.broadcasting && !model.running)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Duplicar pantalla
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duplicar la pantalla del iPhone")
                        .font(.headline)
                    Text("Para ver Waze, Google Maps u otra app. El iPhone debe ir desbloqueado y en horizontal.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button {
                        model.prepareForBroadcast()
                        BroadcastPicker.shared.open()
                    } label: {
                        Label(
                            model.broadcasting ? "Detener duplicado" : "Duplicar pantalla",
                            systemImage: "rectangle.on.rectangle"
                        )
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.broadcasting ? .red : .green)
                    .background(PickerHost().frame(width: 1, height: 1))
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                DisclosureGroup("Opciones avanzadas") {
                    TextField("IP de la moto (vacío = automática)", text: $model.manualIp)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled(true)
                        .disabled(model.running)
                        .padding(.top, 6)
                }
                .font(.footnote)

                HStack(spacing: 8) {
                    Text(model.broadcasting && !model.running ? "Registro del duplicado" : "Registro")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button(model.copied ? "¡Copiado!" : "Copiar registro") {
                        model.copyLog()
                    }
                    .buttonStyle(.bordered)
                    Button("Borrar") {
                        logBus.clear()
                    }
                    .buttonStyle(.bordered)
                }

                LogView(lines: shownLines)
                    .frame(height: 260)
            }
            .padding()
        }
    }
}

struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.suffix(400).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(6)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .onChange(of: lines.count) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
