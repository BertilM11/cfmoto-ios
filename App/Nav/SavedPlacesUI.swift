// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import CoreLocation

/// 0.7.2: lo que aparece al tocar el buscador sin escribir nada: pegar una ubicación copiada,
/// los destinos guardados (Casa, Trabajo, favoritos) y los recientes.
struct SavedPlacesPanel: View {
    @ObservedObject private var places = SavedPlaces.shared
    let palette: Palette
    let onPaste: (String) -> Void
    let onGo: (SavedPlace) -> Void
    @State private var renaming: SavedPlace?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            pasteRow
            let saved = places.ordered
            if !saved.isEmpty {
                header("Guardados")
                ForEach(saved) { place in
                    row(place, icon: place.kind.icon, detail: place.kind == .star ? nil : place.kind.title)
                        .contextMenu {
                            Button {
                                newName = place.name
                                renaming = place
                            } label: { Label("Cambiar nombre", systemImage: "pencil") }
                            Button(role: .destructive) {
                                places.remove(place)
                            } label: { Label("Quitar de guardados", systemImage: "trash") }
                        }
                }
            }
            let recent = places.recent.filter { places.savedMatch(lat: $0.lat, lon: $0.lon) == nil }
            if !recent.isEmpty {
                header("Recientes")
                ForEach(recent.prefix(5)) { place in
                    row(place, icon: "clock.arrow.circlepath", detail: nil)
                        .contextMenu {
                            ForEach(SavedPlace.Kind.allCases, id: \.self) { kind in
                                Button {
                                    places.save(name: kind == .star ? place.name : kind.title, lat: place.lat, lon: place.lon, kind: kind)
                                } label: { Label("Guardar como \(kind.title)", systemImage: kind.icon) }
                            }
                        }
                }
            }
            if saved.isEmpty && recent.isEmpty {
                Text("Para guardar un destino tocá ☆ al ver la ruta. También podés pegar coordenadas o un enlace de Google Maps, o mantener presionado un punto del mapa.")
                    .font(.system(size: 13))
                    .foregroundColor(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                Text("Mantené presionado un destino para guardarlo o cambiarle el nombre.")
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
        .alert("Cambiar nombre", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                if let place = renaming { places.rename(place, to: newName) }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
    }

    /// El botón del sistema para pegar no muestra el aviso de «permitir pegar».
    private var pasteRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 20))
                .frame(width: 26)
                .foregroundColor(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pegar ubicación")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.cardText)
                Text("Coordenadas o enlace de Google Maps, Waze…")
                    .font(.system(size: 13))
                    .foregroundColor(palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first {
                    DispatchQueue.main.async { onPaste(text) }
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .tint(palette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func row(_ place: SavedPlace, icon: String, detail: String?) -> some View {
        Button {
            onGo(place)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 26)
                    .foregroundColor(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.cardText)
                        .lineLimit(1)
                    if let detail = detail, detail != place.name {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundColor(palette.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 0.7.2: la estrella de la tarjeta de la ruta: guarda el destino como Casa, Trabajo o
/// favorito, o lo quita si ya estaba guardado.
struct SaveDestinationButton: View {
    @ObservedObject var engine: NavEngine
    let palette: Palette
    @ObservedObject private var places = SavedPlaces.shared
    @State private var asking = false

    private var match: SavedPlace? {
        guard let c = engine.destinationCoordinate else { return nil }
        return places.savedMatch(lat: c.latitude, lon: c.longitude)
    }

    var body: some View {
        Button {
            asking = true
        } label: {
            Image(systemName: match == nil ? "star" : (match?.kind.icon ?? "star.fill"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(match == nil ? palette.secondaryText : palette.accent)
                .frame(width: 32, height: 32)
                .background(palette.field, in: Circle())
        }
        .disabled(engine.destinationCoordinate == nil)
        .accessibilityLabel(match == nil ? "Guardar destino" : "Destino guardado")
        .confirmationDialog(match == nil ? "Guardar «\(engine.destinationName)»" : "«\(match?.name ?? "")» está guardado",
                            isPresented: $asking, titleVisibility: .visible) {
            if let saved = match {
                Button("Quitar de guardados", role: .destructive) { places.remove(saved) }
            } else if let c = engine.destinationCoordinate {
                Button("Guardar como Casa") { places.save(name: "Casa", lat: c.latitude, lon: c.longitude, kind: .home) }
                Button("Guardar como Trabajo") { places.save(name: "Trabajo", lat: c.latitude, lon: c.longitude, kind: .work) }
                Button("Guardar en favoritos") { places.save(name: engine.destinationName, lat: c.latitude, lon: c.longitude, kind: .star) }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}
