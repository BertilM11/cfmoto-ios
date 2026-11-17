// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// "Mi pantalla": editor del panel. La vista previa es el mismo dibujo que recibe la moto y
/// las zonas punteadas se arrastran una sobre otra para intercambiarlas.
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
                    .overlay { GeometryReader { g in slots(in: g.size) } }
                Text("Arrastra una zona sobre otra para intercambiarlas. Toca su etiqueta para cambiar el módulo u ocultarlo. Los cambios se aplican al instante en la moto.")
                    .font(.caption).foregroundColor(Brand.dim)
                Toggle("Vista previa con datos de demostración", isOn: $demo)
                    .font(.subheadline)
                    .tint(Brand.blue)

                Text("Modo").font(.headline)
                ModeChips()

                Card {
                    Text("Distribución").font(.headline)
                    Picker("Plantilla", selection: Binding(get: { layout.template }, set: { t in store.edit { $0.setTemplate(t) } })) {
                        ForEach(DashTemplate.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
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
                    Text("Tema del panel").font(.footnote).foregroundColor(Brand.dim)
                    Picker("Tema", selection: $store.config.theme) {
                        ForEach(DashTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .tint(Brand.blue)

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

    private func slots(in size: CGSize) -> some View {
        let scale = size.width / 800
        let usable = DashLayoutEngine.usableArea(width: 800, height: 400, reservedBottom: HUDRenderer.reservedBottom)
        let gap = (6 * usable.height / 400).rounded()
        let current = layout
        let rects = DashLayoutEngine.slotRects(current, in: usable.insetBy(dx: gap, dy: gap), gap: gap)
        return ZStack {
            ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                SlotHandle(index: index, module: index < current.slots.count ? current.slots[index] : nil)
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .position(x: rect.midX * scale, y: rect.midY * scale)
            }
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
