// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// "Mi pantalla": editor del panel. La vista previa es el mismo dibujo que recibe la moto.
/// En "Mapa completo" las tarjetas se arrastran a otra esquina; en los diseños por zonas, las
/// zonas se arrastran una sobre otra para intercambiarlas.
struct MyScreenEditor: View {
    @ObservedObject private var store = DashStore.shared
    @State private var demo = true
    @State private var asking = false
    @State private var newName = ""
    @State private var renaming: DashProfile?
    @State private var renameText = ""

    private var layout: DashLayout { store.config.layout }

    var body: some View {
        NavigationStack {
            DarkPage(title: "Mi pantalla") {
                TFTPreview(demo: demo)
                    .overlay { GeometryReader { g in handles(in: g.size) } }
                Text(layout.template == .overlay
                     ? "Arrastra una tarjeta a otra esquina o sobre otra para intercambiarlas. Toca su etiqueta para moverla, cambiar su tamaño u ocultarla."
                     : "Arrastra una zona sobre otra para intercambiarlas. Toca su etiqueta para cambiar el módulo u ocultarlo.")
                    .font(.caption).foregroundColor(Brand.dim)
                Toggle("Vista previa con datos de demostración", isOn: $demo)
                    .font(.subheadline)
                    .tint(Brand.blue)
                if demo {
                    Text("En la demostración el mapa es simplificado. Con tu ubicación o una ruta real se ven las calles de Apple Maps.")
                        .font(.caption).foregroundColor(Brand.dim)
                }

                Text("Modo").font(.headline)
                ModeChips()

                Card {
                    Text("Distribución").font(.headline)
                    Picker("Plantilla", selection: Binding(get: { layout.template }, set: { t in store.edit { $0.setTemplate(t) } })) {
                        ForEach(DashTemplate.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if layout.template == .overlay {
                        overlayControls
                    } else {
                        if layout.template != .full {
                            Text("Ancho de la zona principal").font(.footnote).foregroundColor(Brand.dim)
                            Slider(value: Binding(get: { layout.split }, set: { v in store.edit { $0.split = v } }), in: DashLayout.splitRange)
                            Toggle("Zona principal a la derecha", isOn: Binding(get: { layout.mirrored }, set: { v in store.edit { $0.mirrored = v } }))
                                .font(.subheadline)
                        }
                        if layout.template == .mainSide {
                            Text("Alto de la zona lateral de arriba").font(.footnote).foregroundColor(Brand.dim)
                            Slider(value: Binding(get: { layout.sideSplit }, set: { v in store.edit { $0.sideSplit = v } }), in: DashLayout.sideRange)
                        }
                    }
                    Text("Tema del panel").font(.footnote).foregroundColor(Brand.dim)
                    Picker("Tema", selection: $store.config.theme) {
                        ForEach(DashTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .tint(Brand.blue)

                MapSettingsCard()

                Card {
                    Text("Perfiles").font(.headline)
                    ForEach(store.config.profiles) { profile in
                        HStack {
                            Button {
                                store.apply(profile)
                            } label: {
                                HStack {
                                    Image(systemName: store.config.activeProfile == profile.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(Brand.blue)
                                    Text(profile.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button("Renombrar") {
                                    renameText = profile.name
                                    renaming = profile
                                }
                                Button("Eliminar", role: .destructive) { store.delete(profile.id) }
                            } label: {
                                Image(systemName: "ellipsis").padding(8).foregroundColor(Brand.dim)
                            }
                        }
                    }
                    Button {
                        newName = ""
                        asking = true
                    } label: {
                        Label("Guardar el diseño actual como perfil", systemImage: "plus.circle.fill")
                    }
                    .tint(Brand.blue)
                }

                Button(role: .destructive) {
                    store.restoreDefaults()
                } label: {
                    Label("Restaurar la distribución predeterminada", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .alert("Nuevo perfil", isPresented: $asking) {
                TextField("Nombre", text: $newName)
                Button("Guardar") { store.saveProfile(named: newName) }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Renombrar perfil", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nombre", text: $renameText)
                Button("Guardar") {
                    if let p = renaming { store.rename(p.id, to: renameText) }
                    renaming = nil
                }
                Button("Cancelar", role: .cancel) { renaming = nil }
            }
        }
    }

    // MARK: - Tarjetas sobre el mapa

    private var overlayControls: some View {
        let o = layout.overlay
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tarjetas sobre el mapa").font(.footnote).foregroundColor(Brand.dim)
            ForEach(OverlayItem.editable, id: \.self) { item in
                HStack {
                    Toggle(isOn: Binding(get: { o.isOn(item) }, set: { v in store.edit { $0.overlay.set(item, on: v) } })) {
                        Label(item.title, systemImage: item.symbol).font(.subheadline)
                    }
                }
                if o.isOn(item) {
                    HStack {
                        Picker("Lugar", selection: Binding(get: { o.spot(item) }, set: { v in store.edit { $0.overlay.move(item, to: v) } })) {
                            ForEach(CardSpot.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        if item.resizable {
                            Picker("Tamaño", selection: Binding(get: { o.size(item) }, set: { v in store.edit { $0.overlay.resize(item, to: v) } })) {
                                ForEach(CardSize.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.leading, 30)
                }
            }
        }
    }

    // MARK: - Asas sobre la vista previa

    private func handles(in size: CGSize) -> some View {
        let scale = size.width / 800
        let usable = DashLayoutEngine.usableArea(width: 800, height: 400, reservedBottom: HUDRenderer.reservedBottom)
        let current = layout
        let previewHeight = size.width / 2
        return ZStack {
            if current.template == .overlay {
                ForEach(CardSpot.allCases) { spot in
                    SpotTarget(spot: spot)
                        .frame(width: spot.region.width * size.width, height: spot.region.height * previewHeight)
                        .position(x: spot.region.midX * size.width, y: spot.region.midY * previewHeight)
                }
                let cards = DashLayoutEngine.overlayCards(current.overlay, in: usable, k: 1, showNotices: true)
                ForEach(cards.filter { $0.item != .compass }, id: \.item) { card in
                    CardHandle(item: card.item)
                        .frame(width: card.rect.width * scale, height: card.rect.height * scale)
                        .position(x: card.rect.midX * scale, y: card.rect.midY * scale)
                }
            } else {
                let gap = (6 * usable.height / 400).rounded()
                let rects = DashLayoutEngine.slotRects(current, in: usable.insetBy(dx: gap, dy: gap), gap: gap)
                ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                    SlotHandle(index: index, module: index < current.slots.count ? current.slots[index] : nil)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .position(x: rect.midX * scale, y: rect.midY * scale)
                }
            }
        }
    }
}

/// Ajustes del mapa de calles (compartidos por todos los modos).
struct MapSettingsCard: View {
    @ObservedObject private var store = DashStore.shared

    var body: some View {
        Card {
            Text("Mapa").font(.headline)
            Toggle("Calles de Apple Maps", isOn: $store.config.map.streets)
            if store.config.map.streets {
                Picker("Estilo", selection: $store.config.map.style) {
                    ForEach(MapStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Vista inclinada (3D)", isOn: $store.config.map.threeD)
                Toggle("Tráfico en colores", isOn: $store.config.map.traffic)
                Toggle("Norte siempre arriba", isOn: $store.config.map.northUp)
                HStack {
                    Text("Letras del mapa")
                    Spacer()
                    Picker("Letras", selection: $store.config.map.labels) {
                        ForEach(MapLabelSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Text("Zoom automático: \(store.config.map.zoom < 0.95 ? "más cerca" : (store.config.map.zoom > 1.05 ? "más lejos" : "normal"))")
                    .font(.footnote).foregroundColor(Brand.dim)
                Slider(value: $store.config.map.zoom, in: MapSettings.zoomRange)
                Text("El mapa se acerca antes de cada giro y se aleja con la velocidad. Las calles se actualizan con CFMoto Link abierta; con el iPhone bloqueado se usan las imágenes del recorrido que la app guarda al empezar la ruta, así que déjala abierta unos segundos al salir. El tráfico se ve en las calles cuando Apple tiene datos de esa zona.")
                    .font(.caption).foregroundColor(Brand.dim)
            } else {
                Text("Sin calles: la moto muestra solo la ruta sobre fondo liso (no necesita datos móviles).")
                    .font(.caption).foregroundColor(Brand.dim)
            }
        }
        .font(.subheadline)
        .tint(Brand.blue)
    }
}

/// Zona de la vista previa donde se puede soltar una tarjeta.
private struct SpotTarget: View {
    let spot: CardSpot
    @State private var targeted = false

    var body: some View {
        Rectangle()
            .fill(targeted ? Brand.blue.opacity(0.25) : Color.white.opacity(0.001))
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first.flatMap({ OverlayItem(rawValue: $0) }) else { return false }
                DashStore.shared.edit { $0.overlay.move(item, to: spot) }
                return true
            } isTargeted: { targeted = $0 }
    }
}

private struct CardHandle: View {
    let item: OverlayItem
    @State private var targeted = false

    var body: some View {
        let store = DashStore.shared
        let o = store.config.layout.overlay
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(targeted ? Brand.blue : Color.white.opacity(0.6), style: StrokeStyle(lineWidth: targeted ? 3 : 1.5, dash: [6, 4]))
            .background(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .draggable(item.rawValue) {
                Label(item.title, systemImage: "hand.draw.fill")
                    .font(.caption.bold())
                    .padding(8)
                    .background(Brand.blue, in: Capsule())
                    .foregroundColor(.white)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let other = items.first.flatMap({ OverlayItem(rawValue: $0) }), other != item else { return false }
                store.edit { $0.overlay.swap(item, other) }
                return true
            } isTargeted: { targeted = $0 }
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Menu("Mover a…") {
                        ForEach(CardSpot.allCases) { spot in
                            Button {
                                store.edit { $0.overlay.move(item, to: spot) }
                            } label: {
                                if o.spot(item) == spot { Label(spot.title, systemImage: "checkmark") } else { Text(spot.title) }
                            }
                        }
                    }
                    if item.resizable {
                        Button(o.size(item) == .compact ? "Hacerla grande" : "Hacerla compacta") {
                            store.edit { $0.overlay.resize(item, to: o.size(item) == .compact ? .large : .compact) }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.edit { $0.overlay.set(item, on: false) }
                    } label: {
                        Label("Ocultar", systemImage: "eye.slash")
                    }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Brand.blue, in: Capsule())
                        .foregroundColor(.white)
                }
                .padding(4)
            }
    }
}

private struct SlotHandle: View {
    let index: Int
    let module: DashModule?
    @State private var targeted = false

    var body: some View {
        let store = DashStore.shared
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(targeted ? Brand.blue : Color.white.opacity(0.6), style: StrokeStyle(lineWidth: targeted ? 3 : 1.5, dash: [6, 4]))
            .background(Color.white.opacity(module == nil ? 0.08 : 0.001))
            .contentShape(Rectangle())
            .draggable("\(index)") {
                Label(module?.title ?? "Zona vacía", systemImage: "hand.draw.fill")
                    .font(.caption.bold())
                    .padding(8)
                    .background(Brand.blue, in: Capsule())
                    .foregroundColor(.white)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let from = items.first.flatMap({ Int($0) }), from != index else { return false }
                store.edit { $0.swapSlots(from, index) }
                return true
            } isTargeted: { targeted = $0 }
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    ForEach(DashModule.allCases) { m in
                        Button {
                            store.edit { $0.place(m, at: index) }
                        } label: {
                            Label(m.title, systemImage: m.symbol)
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.edit { $0.place(nil, at: index) }
                    } label: {
                        Label("Ocultar esta zona", systemImage: "eye.slash")
                    }
                } label: {
                    Label(module?.title ?? "Vacía", systemImage: module?.symbol ?? "plus")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Brand.blue, in: Capsule())
                        .foregroundColor(.white)
                }
                .padding(4)
            }
    }
}
