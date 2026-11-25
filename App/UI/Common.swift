// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

enum Brand {
    static let bg = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let card = Color(red: 0.055, green: 0.082, blue: 0.125)
    static let blue = Color(red: 0.12, green: 0.48, blue: 1.0)
    static let dim = Color(red: 0.6, green: 0.65, blue: 0.73)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Chip: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Brand.blue : Brand.card, in: Capsule())
            .foregroundColor(.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Fondo oscuro y barra de título comunes a las pantallas nuevas.
struct DarkPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // El título va dibujado aquí: así siempre es blanco, esté el iPhone en modo
                // claro u oscuro.
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Brand.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .toolbarBackground(Brand.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .foregroundColor(.white)
    }
}

/// Imagen del panel tal como la recibe la moto. Debajo se señala la franja donde la moto pone
/// sus propios indicadores (la app no la controla).
struct TFTImage: View {
    let image: CGImage?
    var showBikeBand = true
    @AppStorage("franjaLibre") private var reserve = false
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let image = image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                } else {
                    Color.black
                }
            }
            .aspectRatio(2, contentMode: .fit)
            .overlay {
                GeometryReader { g in
                    if reserve {
                        Text("Parte vacía a petición (Ajustes)")
                            .font(.system(size: max(8, g.size.height * 0.055), weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(width: g.size.width, height: g.size.height * 0.22)
                            .position(x: g.size.width / 2, y: g.size.height * 0.89)
                    }
                }
            }
            if showBikeBand {
                Text("Franja de la moto: velocidad, rpm, marcha y testigos")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.black)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// Vista previa viva. Usa el mismo dibujo que se envía a la moto.
struct TFTPreview: View {
    @ObservedObject private var store = DashStore.shared
    var demo: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            TFTImage(image: store.previewImage(demo: demo, now: context.date))
        }
    }
}

struct ModeChips: View {
    @ObservedObject private var store = DashStore.shared
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DashMode.primary + DashMode.others) { mode in
                    Button(mode.short) { store.setMode(mode) }
                        .buttonStyle(Chip(selected: store.config.mode == mode))
                }
            }
        }
    }
}

struct RootTabs: View {
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    @ObservedObject private var requests = NavRequests.shared
    var body: some View {
        TabView(selection: $tab) {
            HomeScreen(tab: $tab)
                .tabItem { Label("Inicio", systemImage: "house.fill") }.tag(0)
            NavScreen()
                .tabItem { Label("Navegación", systemImage: "location.north.line.fill") }.tag(1)
            MyScreenEditor()
                .tabItem { Label("Mi pantalla", systemImage: "rectangle.3.group.fill") }.tag(2)
            NavigationStack { MusicScreen() }
                .tabItem { Label("Música", systemImage: "music.note") }.tag(3)
            MoreScreen()
                .tabItem { Label("Más", systemImage: "ellipsis.circle.fill") }.tag(4)
        }
        .tint(Brand.blue)
        .toolbarColorScheme(.dark, for: .tabBar)
        // 0.8.0: un pedido de Siri («Llévame a casa») abre la pestaña de navegación.
        .onReceive(requests.$pending.compactMap { $0 }) { _ in tab = 1 }
        .onAppear {
            DashStore.shared.start()
            MusicService.shared.start()
            TripRecorder.shared.start()
            SpotifyWeb.shared.start()
        }
    }
}

struct MoreScreen: View {
    /// Solo para la prueba automática ("-more personalizacion"): abre esa pantalla al empezar.
    @State private var openPersonalization = UserDefaults.standard.string(forKey: "more") == "personalizacion"
    @State private var openTrips = UserDefaults.standard.string(forKey: "more") == "viajes"

    var body: some View {
        NavigationStack {
            DarkPage(title: "Más") {
                link("Viajes", "point.topleft.down.curvedto.point.bottomright.up", "Recorridos grabados: km, tiempo, velocidad y GPX") { TripsScreen() }
                link("Personalización del tablero", "slider.horizontal.3", "Navegación, día y noche, música y pantalla") { PersonalizationScreen() }
                link("Modos", "square.grid.2x2.fill", "Modos predeterminados y cambios automáticos") { ModesScreen() }
                link("Notificaciones", "bell.fill", "Fuentes, privacidad y duración de los avisos") { NoticesScreen() }
                link("Conexión", "antenna.radiowaves.left.and.right", "Estado de la moto, diagnóstico y registro") { ConnectionScreen() }
                link("Diagnóstico", "stethoscope", "Vídeo, GPS, mapa guardado, memoria y red; exportar informe") { DiagnosticsScreen() }
                link("Ajustes", "gearshape.fill", "Tema, franja de la moto y restauración") { SettingsScreen() }
            }
            .navigationDestination(isPresented: $openPersonalization) { PersonalizationScreen() }
            .navigationDestination(isPresented: $openTrips) { TripsScreen() }
        }
    }

    private func link<D: View>(_ title: String, _ symbol: String, _ detail: String, @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.title3).foregroundColor(Brand.blue).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(detail).font(.footnote).foregroundColor(Brand.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(Brand.dim)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ConnectionScreen: View {
    var body: some View {
        MotoPanel(model: LinkModel.shared)
            .background(Brand.bg.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Conexión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
