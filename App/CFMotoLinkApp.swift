// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit
import ReplayKit

@main
struct CFMotoLinkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class LinkModel: ObservableObject {
    @Published var running = false
    @Published var status = "Sin conectar"
    @Published var manualIp = ""
    @Published var copied = false
    /// Registro de la extensión de transmisión (vacío si no está activa).
    @Published var broadcastLog: [String] = []
    @Published var broadcasting = false

    private let link = BikeLink()
    private var pollTimer: Timer?

    init() {
        link.onStatus = { [weak self] s in
            DispatchQueue.main.async { self?.status = s }
        }
    }

    func connect() {
        running = true
        status = "Iniciando…"
        UIApplication.shared.isIdleTimerDisabled = true
        let ip = manualIp
        DispatchQueue.global(qos: .userInitiated).async { [link] in
            link.start(manualBikeIp: ip)
        }
    }

    func disconnect() {
        guard running else { return }
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
        DispatchQueue.global(qos: .userInitiated).async { [link] in
            link.stop()
        }
    }

    /// Antes de transmitir la pantalla hay que soltar los puertos de la prueba.
    func prepareForBroadcast() {
        if running {
            logLine("se detiene la prueba para dejar los puertos libres a la transmisión")
            running = false
            UIApplication.shared.isIdleTimerDisabled = false
            link.stop()
        }
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let text = LogShare.fetch()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let t = text {
                        self.broadcasting = true
                        self.broadcastLog = t.isEmpty ? [] : t.components(separatedBy: "\n")
                    } else {
                        self.broadcasting = false
                    }
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func copyLog() {
        var text = LogBus.shared.text
        if !broadcastLog.isEmpty {
            text += "\n\n==== Registro de la transmisión de pantalla ====\n" + broadcastLog.joined(separator: "\n")
        }
        UIPasteboard.general.string = text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.copied = false
        }
    }
}

/// Selector del sistema para iniciar/detener la transmisión de pantalla, limitado a nuestra
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

struct ContentView: View {
    @StateObject private var model = LinkModel()
    @ObservedObject private var logBus = LogBus.shared
    @Environment(\.scenePhase) private var scenePhase

    private var shownLines: [String] {
        if model.broadcasting && !model.running {
            return model.broadcastLog
        }
        return logBus.lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CFMoto Link")
                .font(.title2.bold())
            Text("Pantalla del iPhone → pantalla CFMOTO")
                .font(.footnote)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. En la moto, abre la pantalla del código QR y déjala abierta.")
                Text("2. En Ajustes > Wi-Fi, conéctate a DIRECT-…-CFMOTO (clave 12345678).")
                Text("3. Pulsa Transmitir pantalla y luego Iniciar transmisión. Después usa Maps, Spotify o lo que quieras.")
            }
            .font(.footnote)

            Button {
                model.prepareForBroadcast()
                BroadcastPicker.shared.open()
            } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(model.broadcasting ? "Detener transmisión" : "Transmitir pantalla a la moto")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.broadcasting ? .red : .green)
            .background(PickerHost().frame(width: 1, height: 1))

            HStack {
                Circle()
                    .fill(model.broadcasting || model.running ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(model.broadcasting ? "Transmitiendo pantalla" : model.status)
                    .font(.subheadline.weight(.semibold))
            }

            DisclosureGroup("Prueba con imagen de prueba") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("IP de la moto (vacío = automática)", text: $model.manualIp)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .disableAutocorrection(true)
                        .disabled(model.running)
                    Button(model.running ? "Detener prueba" : "Conectar con imagen de prueba") {
                        if model.running {
                            model.disconnect()
                        } else {
                            model.connect()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(model.running ? .red : .blue)
                    .disabled(model.broadcasting)
                }
                .padding(.top, 4)
            }
            .font(.footnote)

            HStack(spacing: 8) {
                Text(model.broadcasting && !model.running ? "Registro de la transmisión" : "Registro")
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(shownLines.suffix(400).enumerated()), id: \.offset) { _, line in
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
                .onChange(of: shownLines.count) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .padding()
        .onAppear { model.startPolling() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.startPolling()
            } else {
                model.stopPolling()
            }
        }
    }
}
