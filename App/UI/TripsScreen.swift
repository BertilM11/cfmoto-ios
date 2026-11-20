// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import MapKit

/// 0.8.0: historial de viajes grabados.
struct TripsScreen: View {
    @ObservedObject private var recorder = TripRecorder.shared

    var body: some View {
        DarkPage(title: "Viajes") {
            if recorder.recording {
                Card {
                    Label("Grabando el viaje actual", systemImage: "record.circle")
                        .foregroundColor(.red)
                        .font(.headline)
                    Text("Se guarda solo al terminar (3 minutos sin la moto ni navegación).")
                        .font(.footnote).foregroundColor(Brand.dim)
                }
            }
            let trips = recorder.trips
            if trips.isEmpty {
                Card {
                    Text("Todavía no hay viajes").font(.headline)
                    Text("Los viajes se graban solos mientras la app está conectada a la moto o navegando. Se guardan los de más de 300 m, solo en este iPhone.")
                        .font(.footnote).foregroundColor(Brand.dim)
                }
            } else {
                summary(trips)
                ForEach(trips) { trip in
                    NavigationLink {
                        TripDetailScreen(trip: trip)
                    } label: {
                        row(trip)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func summary(_ trips: [Trip]) -> some View {
        let km = trips.reduce(0) { $0 + $1.distance } / 1000
        let hours = trips.reduce(0) { $0 + $1.movingTime } / 3600
        return Card {
            HStack {
                stat(String(format: "%.0f km", km), "en total")
                Spacer()
                stat("\(trips.count)", trips.count == 1 ? "viaje" : "viajes")
                Spacer()
                stat(String(format: "%.1f h", hours), "en movimiento")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(Brand.dim)
        }
    }

    private func row(_ trip: Trip) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 20))
                .foregroundColor(Brand.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(TripFormat.line(trip)).font(.footnote).foregroundColor(Brand.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundColor(Brand.dim)
        }
        .padding(14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum TripFormat {
    static func km(_ m: Double) -> String { String(format: m < 10_000 ? "%.1f km" : "%.0f km", m / 1000) }
    static func kmh(_ ms: Double) -> String { String(format: "%.0f km/h", ms * 3.6) }
    static func time(_ s: Double) -> String {
        let m = Int((s / 60).rounded())
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }
    static func line(_ t: Trip) -> String {
        "\(km(t.distance)) · \(time(t.duration)) · promedio \(kmh(t.averageSpeed))"
    }
}

struct TripDetailScreen: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        DarkPage(title: "Viaje") {
            Text(trip.title).font(.headline)
            TripMap(trip: trip)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Card {
                grid
            }
            ShareLink(item: TripRecorder.shared.gpxFile(trip)) {
                Label("Exportar recorrido (GPX)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Brand.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundColor(.white)
                    .font(.headline)
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Borrar este viaje", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .confirmationDialog("¿Borrar este viaje?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    TripRecorder.shared.delete(trip)
                    dismiss()
                }
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 12) {
            HStack {
                item(TripFormat.km(trip.distance), "distancia")
                Spacer()
                item(TripFormat.time(trip.duration), "duración")
            }
            HStack {
                item(TripFormat.time(trip.movingTime), "en movimiento")
                Spacer()
                item(TripFormat.kmh(trip.averageSpeed), "promedio")
            }
            HStack {
                item(TripFormat.kmh(trip.maxSpeed), "máxima (GPS)")
                Spacer()
                item("\(trip.points.count)", "puntos")
            }
        }
    }

    private func item(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(Brand.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El recorrido sobre el mapa de Apple (son datos propios del GPS, no del mapa).
struct TripMap: UIViewRepresentable {
    let trip: Trip

    func makeCoordinator() -> Delegate { Delegate() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        let coords = trip.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        if coords.count >= 2 {
            let line = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(line)
            map.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
            let a = MKPointAnnotation(); a.coordinate = coords[0]; a.title = "Inicio"
            let b = MKPointAnnotation(); b.coordinate = coords[coords.count - 1]; b.title = "Final"
            map.addAnnotations([a, b])
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}

    final class Delegate: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = UIColor(red: 0.12, green: 0.48, blue: 1, alpha: 1)
            r.lineWidth = 5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
    }
}
