// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// "Personalización del tablero": todas las opciones del panel de la moto en un solo sitio.
/// Todo se guarda al momento y se recupera al volver a abrir la app.
struct PersonalizationScreen: View {
    @ObservedObject private var store = DashStore.shared
    @State private var demo = false

    private var layout: DashLayout { store.config.layout }
    /// El diseño tiene mapa con la maniobra encima (mapa completo o una zona de navegación).
    private var hasNav: Bool { layout.template == .overlay || layout.slots.contains(.nav) }

    var body: some View {
        DarkPage(title: "Personalización del tablero") {
            TFTPreview(demo: demo)
            Toggle("Vista previa con datos de demostración", isOn: $demo)
                .font(.footnote).tint(Brand.blue)

            // MARK: Navegación
            Text("Navegación").font(.title3.bold())
            Card {
                Text("Proveedor de navegación").font(.headline)
                NavProviderPicker()
            }
            Card {
                Text("Día y noche").font(.headline)
                Picker("Apariencia", selection: $store.config.theme) {
                    ForEach(DashTheme.allCases) { Text($0.short).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(themeHelp).font(.caption).foregroundColor(Brand.dim)
            }
            .tint(Brand.blue)
            Card {
                Text("Vista del mapa").font(.headline)
                Picker("Vista", selection: $store.config.map.threeD) {
                    Text("2D").tag(false)
                    Text("3D inclinada").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Zoom automático (velocidad y giros)", isOn: $store.config.map.autoZoom)
                Text("Estilo de la ruta").font(.footnote).foregroundColor(Brand.dim)
                Picker("Ruta", selection: $store.config.map.routeStyle) {
                    ForEach(RouteStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .font(.subheadline)
            .tint(Brand.blue)
            MapSettingsCard()

            // MARK: Música
            Text("Música").font(.title3.bold())
            Card {
                Picker("Servicio", selection: $store.config.musicProvider) {
                    ForEach(MusicProvider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Colores de la tarjeta").font(.footnote).foregroundColor(Brand.dim)
                Picker("Colores", selection: $store.config.musicStyle) {
                    ForEach(MusicCardStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                if store.config.musicStyle == .dynamic {
                    Text("Intensidad del color: \(Int(store.config.musicIntensity * 100)) %")
                        .font(.footnote).foregroundColor(Brand.dim)
                    Slider(value: $store.config.musicIntensity, in: 0.2...1)
                    Text("Se toman los colores dominantes de la portada (Spotify o Apple Music) con tonos sobrios; el texto se elige para que siempre se lea. La portada se muestra tal cual.")
                        .font(.caption).foregroundColor(Brand.dim)
                }
                Text("Tamaño de la portada").font(.footnote).foregroundColor(Brand.dim)
                Picker("Portada", selection: $store.config.artworkSize) {
                    ForEach(ArtworkSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Mostrar la portada", isOn: $store.config.showArtwork)
                Toggle("Barra de progreso", isOn: $store.config.showProgress)
                Toggle("Artista", isOn: $store.config.showArtist)
                Toggle("Nombre del servicio y estado", isOn: $store.config.showSource)
            }
            .font(.subheadline)
            .tint(Brand.blue)

            // MARK: Pantalla
            Text("Pantalla").font(.title3.bold())
            Card {
                Text("Modo de visualización").font(.headline)
                ModeChips()
                if hasNav {
                    // 0.6.3: también en la pantalla dividida y en los diseños por zonas con mapa.
                    HStack {
                        Text("Tarjeta de maniobra")
                        Spacer()
                        Picker("Maniobra", selection: Binding(get: { layout.overlay.maneuverSize }, set: { v in store.edit { $0.overlay.maneuverSize = v } })) {
                            ForEach(CardSize.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 190)
                    }
                    if layout.template != .overlay {
                        HStack {
                            Text("Lugar de la maniobra")
                            Spacer()
                            Picker("Lugar", selection: Binding(get: { layout.overlay.maneuverSpot }, set: { v in store.edit { $0.overlay.move(.maneuver, to: v) } })) {
                                ForEach(CardSpot.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                if layout.template == .overlay {
                    HStack {
                        Text("Tarjeta de música")
                        Spacer()
                        Picker("Música", selection: Binding(get: { layout.overlay.musicSize }, set: { v in store.edit { $0.overlay.musicSize = v } })) {
                            ForEach(CardSize.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 190)
                    }
                }
                if hasNav {
                    Text(layout.template == .overlay
                         ? "Cambiar un tamaño pasa al modo 5 (Personalizado). La posición de cada tarjeta se elige arrastrándola en Mi pantalla."
                         : "La tarjeta de la maniobra es la misma que sobre el mapa completo. Cambiar el tamaño o el lugar pasa al modo 5 (Personalizado).")
                        .font(.caption).foregroundColor(Brand.dim)
                }
                Toggle("Animaciones (colores, mapa y ruta nueva)", isOn: $store.config.animations)
                Button(role: .destructive) {
                    store.restoreDefaults()
                } label: {
                    Label("Volver al diseño predeterminado", systemImage: "arrow.counterclockwise")
                }
            }
            .font(.subheadline)
            .tint(Brand.blue)
        }
    }

    private var themeHelp: String {
        switch store.config.theme {
        case .auto: return "Mapa claro de día y oscuro de noche, según el amanecer y el atardecer donde estás (sin ubicación, por la hora). Cambia solo durante la ruta, con un fundido suave."
        case .light: return "Siempre el estilo de día de Apple Maps."
        case .dark: return "Siempre el estilo de noche de Apple Maps."
        }
    }
}
