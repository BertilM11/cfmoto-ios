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
                Text("MotoLink sigue enviando el mapa a la moto")
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
        // Con la pantalla negra el mapa sigue en vivo; esto dice cuánto hay guardado por si se
        // bloquea el iPhone (0.6.3: mismo texto que en Navegación).
        coverage = TFTMap.shared.stats().state.text
    }
}

/// Aviso en Navegación: cuánto mapa queda guardado por si se bloquea el iPhone. 0.6.3: dice
/// si la ruta está completa, si se sigue guardando o si es parcial por la memoria, con los
/// kilómetros que de verdad tienen mapa seguido desde la posición.
struct MapCoverageChip: View {
    let palette: Palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let stats = TFTMap.shared.stats()
            let state = stats.state
            if DashStore.shared.config.map.provider == .osm {
                // 0.7: con el mapa propio no hay nada que descargar.
                let ready = OSMMapData.current != nil
                HStack(spacing: 6) {
                    Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(ready ? "Mapa de Guatemala en el iPhone · sin internet" : "Esta copia no trae el mapa de Guatemala")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ready ? color(.complete) : color(.partial))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if state.kind != .none {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(state.kind))
                        Text(state.text)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    if state.kind != .complete {
                        Text(state.advice)
                            .font(.system(size: 10.5))
                            .foregroundColor(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 0.6.5: si Apple no entrega imágenes, decirlo en vez de parecer parado.
                    if state.kind != .complete && stats.retryIn > 0 {
                        Text(String(format: "Apple no entregó la última imagen (%@). Reintento en %.0f s.", stats.lastError, stats.retryIn))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundColor(color(state.kind))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func icon(_ kind: MapCoverageState.Kind) -> String {
        switch kind {
        case .complete: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        default: return "arrow.down.circle"
        }
    }

    private func color(_ kind: MapCoverageState.Kind) -> Color {
        switch kind {
        case .complete: return Color(red: 0.14, green: 0.76, blue: 0.43)
        case .partial: return Color(red: 0.96, green: 0.62, blue: 0.2)
        default: return palette.secondaryText
        }
    }
}
