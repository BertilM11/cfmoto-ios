// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

/// "Pantalla negra": la app sigue al frente con la pantalla en negro y el brillo al mínimo.
/// Así Apple sigue entregando el mapa en vivo (con el iPhone bloqueado no lo hace) y la moto
/// recibe calles nuevas todo el recorrido. Los toques se ignoran; se sale manteniendo pulsado.
/// En pantallas OLED el negro casi no gasta; en pantallas LCD la luz de fondo sigue encendida
/// al mínimo.
struct PocketScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var savedBrightness: CGFloat = 0.5
    @State private var offset: CGFloat = 0
    @State private var coverage = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Spacer()
                Text("CFMoto Link sigue enviando el mapa a la moto")
                    .font(.footnote)
                    .foregroundColor(Color(white: 0.35))
                if !coverage.isEmpty {
                    Text(coverage)
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.3))
                }
                Text("Mantén pulsado para salir")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.25))
                Spacer().frame(height: 60 + offset)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.2) { dismiss() }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 0
            UIApplication.shared.isIdleTimerDisabled = true
            update()
            logLine("[APP] pantalla negra: la app sigue al frente y el mapa se actualiza en vivo")
        }
        .onDisappear {
            UIScreen.main.brightness = savedBrightness
            logLine("[APP] pantalla negra terminada")
        }
        .onReceive(timer) { _ in
            // El texto cambia de sitio poco a poco para no marcar la pantalla.
            offset = offset > 120 ? 0 : offset + 30
            update()
        }
    }

    private func update() {
        let s = TFTMap.shared.stats()
        coverage = s.routeActive ? "Mapa guardado por delante: \(Diagnostics.km(s.coverage.continuous))" : ""
    }
}

/// Aviso en Navegación: cuánto mapa queda guardado por si se bloquea el iPhone.
struct MapCoverageChip: View {
    let palette: Palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let s = TFTMap.shared.stats()
            if s.routeActive {
                let remaining = s.routeRemaining
                let continuous = s.coverage.continuous
                let ready = continuous >= min(remaining, 5000) - 1
                HStack(spacing: 6) {
                    Image(systemName: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    Text(ready
                         ? "Mapa guardado: \(Diagnostics.km(continuous)) de \(Diagnostics.km(remaining))"
                         : "Guardando el mapa: \(Diagnostics.km(continuous)) de \(Diagnostics.km(remaining))")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ready ? Color(red: 0.14, green: 0.76, blue: 0.43) : palette.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.card.opacity(0.92), in: Capsule())
            }
        }
    }
}
