// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import AppIntents

/// 0.8.0: «Llévame a casa / al trabajo» desde Siri, Atajos o los botones del mapa.
final class NavRequests: ObservableObject {
    static let shared = NavRequests()

    /// Destino guardado pedido (lo atiende la pantalla de navegación).
    @Published var pending: SavedPlace.Kind?
    /// Al terminar de calcular la ruta pedida, empezar la guía sola.
    var autoStart = false

    func go(_ kind: SavedPlace.Kind) {
        autoStart = true
        pending = kind
    }
}

@available(iOS 16.0, *)
struct GoHomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Llévame a casa"
    static var description = IntentDescription("Abre MotoLink y empieza la ruta a tu Casa guardada.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavRequests.shared.go(.home)
        return .result()
    }
}

@available(iOS 16.0, *)
struct GoWorkIntent: AppIntent {
    static var title: LocalizedStringResource = "Llévame al trabajo"
    static var description = IntentDescription("Abre MotoLink y empieza la ruta a tu Trabajo guardado.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavRequests.shared.go(.work)
        return .result()
    }
}

@available(iOS 16.0, *)
struct MotoLinkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GoHomeIntent(), phrases: [
            "Llévame a casa con \(.applicationName)",
            "Ir a casa con \(.applicationName)",
            "\(.applicationName) a casa",
        ], shortTitle: "Llévame a casa", systemImageName: "house.fill")
        AppShortcut(intent: GoWorkIntent(), phrases: [
            "Llévame al trabajo con \(.applicationName)",
            "Ir al trabajo con \(.applicationName)",
            "\(.applicationName) al trabajo",
        ], shortTitle: "Llévame al trabajo", systemImageName: "briefcase.fill")
    }
}

/// Botones de Casa y Trabajo sobre el mapa (solo si están guardados).
struct QuickDestinationChips: View {
    @ObservedObject private var places = SavedPlaces.shared
    let palette: Palette
    let onGo: (SavedPlace) -> Void

    var body: some View {
        let quick = places.ordered.filter { $0.kind != .star }
        if !quick.isEmpty {
            HStack(spacing: 8) {
                ForEach(quick) { place in
                    Button {
                        onGo(place)
                    } label: {
                        Label(place.kind.title, systemImage: place.kind.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(palette.card, in: Capsule())
                            .foregroundColor(palette.cardText)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                    }
                    .accessibilityLabel("Ir a \(place.kind.title)")
                }
                Spacer(minLength: 0)
            }
        }
    }
}
