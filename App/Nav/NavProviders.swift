// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proveedores de navegación: quién da la guía giro a giro.
//
//   Proveedor (CFMoto Link, Mapas de Apple, Google Maps, Waze)
//     → RouteManager (destino que se conserva al cambiar de proveedor)
//     → estado de navegación (HUDState / ExternalGuide)
//     → adaptador de la moto (DashState → dibujo → vídeo H.264)
//     → TFT
//
// Con CFMoto Link la ruta se calcula y se guía aquí (MapKit) y la moto muestra todo. Con una
// app externa, la app se abre con el destino mediante su enlace oficial; esa app no comparte
// su ruta ni sus giros con otras apps, así que la moto muestra el mapa, tu posición y el
// destino, sin giros. Para ver la propia app externa en la moto existe "Duplicar pantalla".
import SwiftUI
import MapKit
import UIKit

final class RouteManager: ObservableObject {
    static let shared = RouteManager()

    @Published private(set) var external: ExternalGuide?
    @Published private(set) var message: String?

    /// Si la app de ese proveedor está instalada (Mapas de Apple y CFMoto Link, siempre).
    func installed(_ p: NavProviderID) -> Bool {
        guard let scheme = p.scheme, let url = URL(string: "\(scheme)://") else { return true }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Botón "Iniciar" de la vista previa: guía aquí o abre la app elegida con el destino.
    /// Solo se da la guía por pasada a la otra app si iOS confirma que se abrió; si no, el
    /// destino y la ruta siguen aquí, listos para guiar con CFMoto Link.
    func start(_ engine: NavEngine) {
        let provider = DashStore.shared.config.navProvider
        guard provider.external else {
            clearExternal()
            message = nil
            engine.startNavigation()
            return
        }
        guard let c = engine.destinationCoordinate else { return }
        let dest = GeoPoint(lat: c.latitude, lon: c.longitude)
        let name = engine.destinationName
        open(provider, dest, name) { [weak self] ok in
            guard let self = self else { return }
            if ok {
                engine.cancel()
                self.setExternal(ExternalGuide(provider: provider, destination: dest, name: name))
                self.say("Guía en \(provider.title). La moto muestra el mapa y el destino; los giros los da \(provider.title).")
            } else {
                DashStore.shared.config.navProvider = .cfmoto
                self.say("No se pudo abrir \(provider.title). La ruta sigue lista aquí: pulsa Iniciar para guiar con CFMoto Link.")
            }
        }
    }

    /// Hay un destino en curso (guía aquí o en otra app).
    func hasDestination(_ engine: NavEngine) -> Bool {
        engine.phase == .navigating || external != nil
    }

    /// Solo cambia el proveedor predeterminado (la ruta en curso sigue como está).
    func setDefault(_ p: NavProviderID) {
        DashStore.shared.config.navProvider = p
    }

    /// Cambia el proveedor predeterminado. Si hay un destino en curso, se conserva: pasa a la
    /// otra app (si iOS la abre) o, al volver a CFMoto Link, se recalcula la ruta aquí.
    func choose(_ p: NavProviderID, engine: NavEngine) {
        let previous = DashStore.shared.config.navProvider
        DashStore.shared.config.navProvider = p
        var current: (GeoPoint, String)?
        if engine.phase == .navigating, let c = engine.destinationCoordinate {
            current = (GeoPoint(lat: c.latitude, lon: c.longitude), engine.destinationName)
        } else if let e = external {
            current = (e.destination, e.name)
        }
        guard let cur = current else { return }
        let (dest, name) = cur
        if p.external {
            open(p, dest, name) { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    if engine.phase == .navigating { engine.cancel() }
                    self.setExternal(ExternalGuide(provider: p, destination: dest, name: name))
                    self.say("Destino pasado a \(p.title): esa app calcula su propia ruta.")
                } else {
                    // La guía que había sigue igual y el proveedor vuelve a ser el de antes.
                    DashStore.shared.config.navProvider = previous
                    self.say("No se pudo abrir \(p.title). La guía actual sigue igual.")
                }
            }
        } else {
            clearExternal()
            if engine.phase != .navigating {
                engine.plan(toCoordinate: CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lon), name: name)
                say("Ruta recalculada por CFMoto Link con el mismo destino. Toca Iniciar.")
            }
        }
    }

    /// Abre la app del proveedor con el destino (enlace oficial) y avisa si iOS la abrió.
    func open(_ p: NavProviderID, _ dest: GeoPoint, _ name: String, done: @escaping (Bool) -> Void) {
        switch p {
        case .cfmoto:
            done(false)
        case .appleMaps:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lon)))
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving], from: nil) { ok in
                DispatchQueue.main.async {
                    logLine("[NAV] destino abierto en Mapas de Apple: \(ok ? "sí" : "no")")
                    done(ok)
                }
            }
        case .googleMaps, .waze:
            let app = installed(p)
            guard let url = p.link(lat: dest.lat, lon: dest.lon, name: name, app: app) else {
                done(false)
                return
            }
            UIApplication.shared.open(url, options: [:]) { ok in
                DispatchQueue.main.async {
                    logLine("[NAV] \(p.title)\(app ? "" : " (web: la app no está instalada)"): \(ok ? "abierto" : "iOS no pudo abrirlo")")
                    done(ok)
                }
            }
        }
    }

    /// Vuelve a abrir la app externa con el mismo destino.
    func reopen() {
        guard let e = external else { return }
        open(e.provider, e.destination, e.name) { [weak self] ok in
            if !ok { self?.say("No se pudo abrir \(e.provider.title).") }
        }
    }

    func stopExternal() {
        clearExternal()
        message = nil
    }

    /// Aviso breve en la vista previa (se borra solo).
    private func say(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            if self?.message == text { self?.message = nil }
        }
    }

    private func clearExternal() {
        if external != nil { setExternal(nil) }
    }

    private func setExternal(_ e: ExternalGuide?) {
        external = e
        DashState.shared.setExternal(e)
    }
}

/// Selector de proveedor con lo que de verdad puede hacer cada uno.
struct NavProviderPicker: View {
    @ObservedObject private var store = DashStore.shared
    @ObservedObject private var routes = RouteManager.shared
    @ObservedObject private var engine = NavEngine.shared
    /// Proveedor elegido mientras hay un destino en curso: se pregunta qué hacer con él.
    @State private var pending: NavProviderID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(NavProviderID.allCases) { p in
                let selected = store.config.navProvider == p
                let ok = routes.installed(p)
                Button {
                    if !selected && routes.hasDestination(engine) {
                        pending = p
                    } else {
                        routes.choose(p, engine: engine)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: p.symbol).foregroundColor(Brand.blue)
                            Text(p.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            if !ok {
                                Text("No instalada · se abre la web").font(.caption2).foregroundColor(.orange)
                            }
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundColor(Brand.blue)
                        }
                        ForEach(Array(p.capabilities.enumerated()), id: \.offset) { _, cap in
                            Label(cap.0, systemImage: cap.1 ? "checkmark" : "xmark")
                                .font(.caption)
                                .foregroundColor(cap.1 ? Brand.dim : .orange)
                        }
                    }
                    .padding(10)
                    .background(selected ? Brand.blue.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Google Maps y Waze no comparten su ruta ni sus giros con otras apps, y el SDK de navegación de Google exige una cuenta de pago con su propia clave. Por eso, con ellos la moto muestra el mapa, tu posición y el destino; la guía y la voz las da su app.")
                .font(.caption).foregroundColor(Brand.dim)
        }
        .confirmationDialog(
            "Hay un destino en curso",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { p in
            Button(p.external ? "Pasar el destino a \(p.title)" : "Guiar aquí con CFMoto Link") {
                routes.choose(p, engine: engine)
            }
            Button("Solo cambiar el predeterminado") { routes.setDefault(p) }
            Button("Cancelar", role: .cancel) {}
        } message: { p in
            Text(p.external
                 ? "\(p.title) se abrirá con el mismo destino y calculará su propia ruta. La moto seguirá mostrando el mapa y el destino, sin giros."
                 : "La ruta se volverá a calcular aquí con el mismo destino; luego toca Iniciar.")
        }
    }
}

/// Aviso en Navegación mientras guía otra app.
struct ExternalGuideCard: View {
    @ObservedObject private var routes = RouteManager.shared
    @ObservedObject private var engine = NavEngine.shared
    let palette: Palette

    var body: some View {
        if let e = routes.external {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: e.provider.symbol).foregroundColor(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Guiando con \(e.provider.title)").font(.system(size: 13, weight: .semibold)).foregroundColor(palette.secondaryText)
                        Text(e.name).font(.system(size: 18, weight: .bold)).foregroundColor(palette.cardText).lineLimit(1)
                    }
                    Spacer()
                }
                Text("La moto muestra el mapa, tu posición y el destino. Los giros y la voz los da \(e.provider.title).")
                    .font(.system(size: 12)).foregroundColor(palette.secondaryText)
                HStack(spacing: 8) {
                    Button("Abrir \(e.provider.title)") { routes.reopen() }
                        .buttonStyle(.borderedProminent).tint(palette.accent)
                    Button("Guiar aquí") { routes.choose(.cfmoto, engine: engine) }
                        .buttonStyle(.bordered)
                    Button("Terminar", role: .destructive) { routes.stopExternal() }
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .padding(16)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: -2)
        }
    }
}
