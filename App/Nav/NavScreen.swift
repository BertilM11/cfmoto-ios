// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import MapKit

/// Pantalla principal: el mapa ocupa todo y encima van el buscador, las rutas y la guía.
struct NavScreen: View {
    @ObservedObject private var engine = NavEngine.shared
    @ObservedObject private var location = LocationService.shared
    @StateObject private var search = PlaceSearch()
    @ObservedObject private var moto = LinkModel.shared
    @AppStorage("tema") private var themeRaw: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @State private var following = true
    @State private var recenterToken = 0
    @State private var showMoto = false
    @State private var showPocket = false
    @FocusState private var searchFocused: Bool

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    private var palette: Palette {
        Palette.resolve(theme, system: systemScheme)
    }

    private var bottomInset: CGFloat {
        switch engine.phase {
        case .preview: return 250
        case .navigating: return 110
        case .arrived: return 110
        default: return 0
        }
    }

    var body: some View {
        let p = palette
        ZStack {
            NavMapView(
                engine: engine,
                palette: p,
                following: $following,
                recenterToken: recenterToken,
                bottomInset: bottomInset
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topArea(p)
                if !searchFocused {
                    HStack(alignment: .top) {
                        Spacer(minLength: 0)
                        floatingButtons(p)
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                }
                Spacer(minLength: 0)
                bottomArea(p)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: engine.phase)
        .animation(.easeOut(duration: 0.2), value: searchFocused)
        .preferredColorScheme(theme == .system ? nil : p.scheme)
        .sheet(isPresented: $showMoto) {
            MotoPanel(model: moto)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showPocket) {
            PocketScreen()
        }
        .onAppear {
            location.activate()
            engine.hudStyle = p.hud
            if let mode = Demo.mode {
                runDemo(mode)
            }
        }
        .onChange(of: p.id) { _ in
            engine.hudStyle = palette.hud
        }
        .onChange(of: engine.phase) { phase in
            if phase == .navigating {
                following = true
                searchFocused = false
            }
        }
    }

    // MARK: - Zonas de la pantalla

    @ViewBuilder
    private func topArea(_ p: Palette) -> some View {
        switch engine.phase {
        case .navigating:
            VStack(spacing: 6) {
                ManeuverBanner(guidance: engine.guidance, simulated: engine.simulating, palette: p)
                MapCoverageChip(palette: p)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        case .arrived:
            EmptyView()
        default:
            VStack(spacing: 8) {
                SearchBar(search: search, palette: p, focused: $searchFocused, onSubmit: submitSearch)
                if searchFocused && !search.results.isEmpty {
                    SearchResults(results: search.results, palette: p, onPick: pick)
                }
                if location.denied {
                    Notice(
                        text: "CFMoto Link necesita tu ubicación para navegar.",
                        palette: p,
                        actionTitle: "Ajustes",
                        action: openSettings
                    )
                }
                if let message = engine.message {
                    Notice(text: message, palette: p)
                }
                if engine.phase == .planning {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Calculando la ruta…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(p.cardText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(p.card, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func bottomArea(_ p: Palette) -> some View {
        switch engine.phase {
        case .preview:
            RoutePreviewCard(
                engine: engine,
                palette: p,
                onStart: { RouteManager.shared.start(engine) },
                onSimulate: { engine.startSimulation() },
                onCancel: cancelPlan
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .navigating:
            TripBar(guidance: engine.guidance, palette: p, muted: $engine.voiceMuted, onEnd: { engine.cancel() })
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .arrived:
            ArrivedCard(name: engine.destinationName, palette: p, onDone: { engine.cancel() })
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            ExternalGuideCard(palette: p)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
    }

    private func floatingButtons(_ p: Palette) -> some View {
        VStack(spacing: 10) {
            Button {
                showMoto = true
            } label: {
                RoundIcon(
                    system: "antenna.radiowaves.left.and.right",
                    palette: p,
                    tint: moto.linked ? p.accent : nil,
                    badge: moto.linked ? Color(red: 0.14, green: 0.76, blue: 0.43) : nil
                )
            }
            Menu {
                Picker("Tema", selection: $themeRaw) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { option in
                        Label(option.title, systemImage: option.icon).tag(option.rawValue)
                    }
                }
            } label: {
                RoundIcon(system: theme.icon, palette: p)
            }
            if engine.phase == .navigating {
                // Pantalla negra: la app sigue al frente y el mapa de la moto sigue al día.
                Button {
                    showPocket = true
                } label: {
                    RoundIcon(system: "moon.zzz.fill", palette: p)
                }
                .accessibilityLabel("Pantalla negra")
            }
            Button {
                following = true
                recenterToken += 1
            } label: {
                RoundIcon(
                    system: following || engine.phase != .navigating ? "location.fill" : "location",
                    palette: p,
                    tint: p.accent
                )
            }
        }
    }

    // MARK: - Acciones

    private func pick(_ completion: MKLocalSearchCompletion) {
        searchFocused = false
        search.resolve(completion) { item in
            guard let item = item else { return }
            search.clear()
            engine.plan(to: item)
        }
    }

    private func submitSearch() {
        let text = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchFocused = false
        search.resolve(text: text) { item in
            guard let item = item else { return }
            search.clear()
            engine.plan(to: item)
        }
    }

    private func cancelPlan() {
        engine.cancel()
        recenterToken += 1
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Demostración para las capturas automáticas

    private func runDemo(_ mode: String) {
        Demo.startDumping()
        switch mode {
        case "search":
            themeRaw = AppTheme.light.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                search.query = "Oakland"
                searchFocused = true
            }
        case "moto":
            themeRaw = AppTheme.light.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showMoto = true
            }
        default:
            themeRaw = (mode == "night" ? AppTheme.night : mode == "dark" ? AppTheme.dark : AppTheme.light).rawValue
            Demo.when({ LocationService.shared.last != nil }) {
                engine.plan(toCoordinate: Demo.destination, name: "Aeropuerto La Aurora")
                if mode != "preview" {
                    Demo.when({ engine.phase == .preview }) {
                        engine.startSimulation(speed: 13, skipToFirstTurn: true)
                    }
                }
            }
        }
    }
}
