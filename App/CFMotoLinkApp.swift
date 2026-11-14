// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

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

    private let link = BikeLink()

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
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
        DispatchQueue.global(qos: .userInitiated).async { [link] in
            link.stop()
        }
    }

    func copyLog() {
        UIPasteboard.general.string = LogBus.shared.text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.copied = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = LinkModel()
    @ObservedObject private var logBus = LogBus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CFMoto Link")
                .font(.title2.bold())
            Text("Prueba de conexión iPhone → pantalla CFMOTO")
                .font(.footnote)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. En la moto, abre la pantalla del código QR y déjala abierta.")
                Text("2. En Ajustes > Wi-Fi, conéctate a DIRECT-…-CFMOTO (clave 12345678).")
                Text("3. Vuelve aquí, pulsa Conectar y acepta el permiso de red local.")
            }
            .font(.footnote)

            HStack {
                Circle()
                    .fill(model.running ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(model.status)
                    .font(.subheadline.weight(.semibold))
            }

            TextField("IP de la moto (vacío = automática)", text: $model.manualIp)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .disableAutocorrection(true)
                .disabled(model.running)

            HStack(spacing: 8) {
                Button(model.running ? "Detener" : "Conectar") {
                    if model.running {
                        model.disconnect()
                    } else {
                        model.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.running ? .red : .blue)

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
                        ForEach(Array(logBus.lines.suffix(400).enumerated()), id: \.offset) { _, line in
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
                .onChange(of: logBus.lines.count) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .padding()
    }
}
