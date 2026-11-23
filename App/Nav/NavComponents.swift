// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import MapKit

/// Icono de maniobra. Usa el mismo dibujo que la pantalla de la moto.
struct ManeuverIcon: View {
    let kind: ManeuverKind
    let color: Color
    let hole: Color

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let stroke = UIColor(color).cgColor
            let background = UIColor(hole).cgColor
            context.withCGContext { cg in
                HUDIcons.draw(kind, in: rect, color: stroke, hole: background, ctx: cg)
            }
        }
    }
}

/// Botón redondo flotante sobre el mapa.
struct RoundIcon: View {
    let system: String
    let palette: Palette
    var tint: Color?
    var badge: Color?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: system)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(tint ?? palette.cardText)
                .frame(width: 48, height: 48)
                .background(palette.card, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            if let badge = badge {
                Circle()
                    .fill(badge)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(palette.card, lineWidth: 2))
                    .offset(x: -2, y: 2)
            }
        }
    }
}

/// Campo de búsqueda de destino.
struct SearchBar: View {
    @ObservedObject var search: PlaceSearch
    let palette: Palette
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(palette.secondaryText)
            TextField("", text: $search.query, prompt: Text("¿A dónde vamos?").foregroundColor(palette.secondaryText))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(palette.cardText)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .onSubmit(onSubmit)
            if search.busy {
                ProgressView()
            } else if !search.query.isEmpty {
                Button {
                    search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(palette.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
    }
}

/// Lista de sugerencias bajo el buscador.
struct SearchResults: View {
    let results: [SearchItem]
    let palette: Palette
    /// Búsqueda en el mapa guardado de OpenStreetMap (se indica de dónde son los datos).
    var offline = false
    /// Resultados de la búsqueda en internet de OpenStreetMap.
    var online = false
    let onPick: (SearchItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                Button {
                    onPick(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: item.kind == .note ? 20 : 22))
                            .frame(width: 26)
                            .foregroundColor(item.kind == .note ? palette.secondaryText : palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(palette.cardText)
                                .lineLimit(item.kind == .note ? 2 : 1)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(palette.secondaryText)
                                    .lineLimit(item.kind == .note ? 3 : 1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < results.count - 1 {
                    Divider().padding(.leading, 50)
                }
            }
            // El aviso de los datos solo si hay lugares de OpenStreetMap en la lista.
            let fromMap = results.contains { $0.kind == .place }
            if online && fromMap {
                Text("Búsqueda en internet: Nominatim · © colaboradores de OpenStreetMap")
                    .font(.system(size: 11))
                    .foregroundColor(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 9)
            } else if offline && fromMap {
                Text("Sin internet, en el mapa de Guatemala · © colaboradores de OpenStreetMap")
                    .font(.system(size: 11))
                    .foregroundColor(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 9)
            }
        }
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
    }
}

/// Aviso corto (errores, permisos).
struct Notice: View {
    let text: String
    let palette: Palette
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(palette.warn)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(palette.cardText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let title = actionTitle, let action = action {
                Button(title, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.accent)
            }
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

/// Tarjeta con las rutas encontradas y el botón para empezar.
struct RoutePreviewCard: View {
    @ObservedObject var engine: NavEngine
    let palette: Palette
    let onStart: () -> Void
    let onSimulate: () -> Void
    let onCancel: () -> Void
    @ObservedObject private var store = DashStore.shared
    @ObservedObject private var routeManager = RouteManager.shared

    private var fastest: Int {
        var best = 0
        for (i, route) in engine.routes.enumerated() where route.expectedTravelTime < engine.routes[best].expectedTravelTime {
            best = i
        }
        return best
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Destino")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.secondaryText)
                    Text(engine.destinationName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(palette.cardText)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                SaveDestinationButton(engine: engine, palette: palette)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(palette.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(palette.field, in: Circle())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(engine.routes.enumerated()), id: \.offset) { index, route in
                        RouteChip(
                            route: route,
                            selected: index == engine.selectedIndex,
                            fastest: index == fastest && engine.routes.count > 1,
                            palette: palette
                        )
                        .onTapGesture { engine.select(index) }
                    }
                }
                .padding(.vertical, 2)
            }

            if let note = routeManager.message {
                Label(note, systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.secondaryText)
            }

            // Quién da la guía (se puede cambiar aquí mismo; el destino se conserva).
            Menu {
                ForEach(NavProviderID.allCases) { p in
                    Button {
                        store.config.navProvider = p
                    } label: {
                        if store.config.navProvider == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.config.navProvider.symbol)
                    Text("Guiar con: \(store.config.navProvider.title)")
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.accent)
            }

            HStack(spacing: 10) {
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Image(systemName: store.config.navProvider.external ? "arrow.up.forward.app.fill" : "location.north.fill")
                        Text(store.config.navProvider.external ? "Abrir en \(store.config.navProvider.title)" : "Iniciar")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Button(action: onSimulate) {
                    Text("Simular")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.cardText)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .background(palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
    }
}

struct RouteChip: View {
    let route: PlannedRoute
    let selected: Bool
    let fastest: Bool
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(HUDFormat.duration(route.estimatedTime))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                if fastest {
                    Text("Más rápida")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((selected ? palette.onAccent : palette.accent).opacity(0.18), in: Capsule())
                }
            }
            Text(HUDFormat.distance(route.distance))
                .font(.system(size: 14, weight: .semibold))
                .opacity(0.9)
            Text(route.name.isEmpty ? "Ruta" : "por " + route.name)
                .font(.system(size: 12))
                .opacity(0.75)
                .lineLimit(1)
        }
        .foregroundColor(selected ? palette.onAccent : palette.cardText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 132, alignment: .leading)
        .background(selected ? palette.accent : palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Indicación de la próxima maniobra, arriba, durante la navegación.
struct ManeuverBanner: View {
    let guidance: Guidance
    let simulated: Bool
    let palette: Palette

    private var tile: Color {
        guidance.rerouting ? palette.warn : palette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tile)
                    ManeuverIcon(kind: guidance.kind, color: palette.onAccent, hole: tile)
                        .padding(9)
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 2) {
                    Text(HUDFormat.distance(guidance.distance))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(palette.bannerText)
                    Text(guidance.rerouting ? "Recalculando la ruta…" : guidance.text)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(palette.bannerText.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if guidance.thenKind != nil || simulated {
                HStack(spacing: 8) {
                    if let then = guidance.thenKind {
                        Text("Luego")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(palette.bannerText.opacity(0.75))
                        ManeuverIcon(kind: then, color: palette.bannerText, hole: palette.banner)
                            .frame(width: 26, height: 26)
                    }
                    Spacer(minLength: 0)
                    if simulated {
                        Text("SIMULACIÓN")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 1, green: 0.69, blue: 0.13), in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(palette.banner, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
}

/// Barra inferior del viaje: llegada, tiempo y distancia restantes, y salir.
struct TripBar: View {
    let guidance: Guidance
    let palette: Palette
    @Binding var muted: Bool
    /// 0.8.0: texto para compartir la llegada.
    var share: String? = nil
    let onEnd: () -> Void

    var body: some View {
        let clock = HUDFormat.clock(guidance.eta)
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.field)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(6, proxy.size.width * CGFloat(max(0, min(1, guidance.fraction)))))
                }
            }
            .frame(height: 5)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(clock.time)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(clock.suffix)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.secondaryText)
                            .lineLimit(1)
                    }
                    Text("llegada")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.secondaryText)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(HUDFormat.duration(guidance.remainingTime))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(HUDFormat.distance(guidance.remainingDistance))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.secondaryText)
                }
                Spacer(minLength: 0)
                if let share = share {
                    ShareLink(item: share) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(palette.cardText)
                            .frame(width: 46, height: 46)
                            .background(palette.field, in: Circle())
                    }
                    .accessibilityLabel("Compartir mi llegada")
                }
                Button {
                    muted.toggle()
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(muted ? palette.secondaryText : palette.cardText)
                        .frame(width: 46, height: 46)
                        .background(palette.field, in: Circle())
                }
                Button(action: onEnd) {
                    Text("Salir")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 46)
                        .background(palette.danger, in: Capsule())
                }
            }
            .foregroundColor(palette.cardText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
    }
}

/// Tarjeta de llegada.
struct ArrivedCard: View {
    let name: String
    let palette: Palette
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 0.14, green: 0.76, blue: 0.43))
                ManeuverIcon(kind: .arrive, color: .white, hole: Color(red: 0.14, green: 0.76, blue: 0.43))
                    .padding(10)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Has llegado")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(palette.cardText)
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(palette.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text("Listo")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(palette.onAccent)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(palette.accent, in: Capsule())
            }
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
    }
}

/// 0.8.1: señal de velocidad máxima en el iPhone (roja si se va más de 5 km/h por encima).
struct SpeedLimitBadge: View {
    let kmh: Int
    let over: Bool

    var body: some View {
        ZStack {
            Circle().fill(over ? Color.red : Color.white)
            Circle().strokeBorder(Color.red, lineWidth: 5)
            Text("\(kmh)")
                .font(.system(size: kmh >= 100 ? 17 : 20, weight: .heavy, design: .rounded))
                .foregroundColor(over ? .white : .black)
        }
        .frame(width: 54, height: 54)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityLabel("Velocidad máxima \(kmh) kilómetros por hora")
    }
}
