// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreLocation
import Combine

/// 0.7.2: un destino guardado o reciente (queda solo en este iPhone).
struct SavedPlace: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case home, work, star

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .work: return "briefcase.fill"
            case .star: return "star.fill"
            }
        }

        var title: String {
            switch self {
            case .home: return "Casa"
            case .work: return "Trabajo"
            case .star: return "Favorito"
            }
        }
    }

    var id = UUID()
    var name: String
    var lat: Double
    var lon: Double
    var kind: Kind = .star

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Mismo punto (a menos de ~30 m).
    func samePlace(lat: Double, lon: Double) -> Bool {
        abs(self.lat - lat) < 0.0003 && abs(self.lon - lon) < 0.0003
    }
}

/// Destinos guardados (Casa, Trabajo y favoritos) y los últimos destinos usados.
final class SavedPlaces: ObservableObject {
    static let shared = SavedPlaces()
    private static let savedKey = "destinosGuardados"
    private static let recentKey = "destinosRecientes"
    static let maxRecent = 8

    @Published private(set) var saved: [SavedPlace] = []
    @Published private(set) var recent: [SavedPlace] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = Self.load(Self.savedKey, defaults)
        recent = Self.load(Self.recentKey, defaults)
    }

    /// Casa y Trabajo primero, después los favoritos en el orden en que se guardaron.
    var ordered: [SavedPlace] {
        saved.filter { $0.kind == .home } + saved.filter { $0.kind == .work } + saved.filter { $0.kind == .star }
    }

    func savedMatch(lat: Double, lon: Double) -> SavedPlace? {
        saved.first { $0.samePlace(lat: lat, lon: lon) }
    }

    /// Guarda (o actualiza) un destino. Casa y Trabajo son únicos: el anterior se reemplaza.
    func save(name: String, lat: Double, lon: Double, kind: SavedPlace.Kind) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = clean.isEmpty ? kind.title : clean
        if kind != .star {
            saved.removeAll { $0.kind == kind }
        }
        if let i = saved.firstIndex(where: { $0.samePlace(lat: lat, lon: lon) }) {
            saved[i].name = label
            saved[i].kind = kind
        } else {
            saved.append(SavedPlace(name: label, lat: lat, lon: lon, kind: kind))
        }
        persist()
    }

    func rename(_ place: SavedPlace, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = saved.firstIndex(where: { $0.id == place.id }) else { return }
        saved[i].name = clean
        persist()
    }

    func remove(_ place: SavedPlace) {
        saved.removeAll { $0.id == place.id }
        recent.removeAll { $0.id == place.id }
        persist()
    }

    /// Anota un destino usado (el más nuevo primero, sin repetir el mismo punto).
    func noteUsed(name: String, lat: Double, lon: Double) {
        recent.removeAll { $0.samePlace(lat: lat, lon: lon) }
        recent.insert(SavedPlace(name: name, lat: lat, lon: lon, kind: .star), at: 0)
        if recent.count > Self.maxRecent {
            recent.removeLast(recent.count - Self.maxRecent)
        }
        persist()
    }

    func clearRecent() {
        recent = []
        persist()
    }

    private func persist() {
        let enc = JSONEncoder()
        defaults.set(try? enc.encode(saved), forKey: Self.savedKey)
        defaults.set(try? enc.encode(recent), forKey: Self.recentKey)
    }

    private static func load(_ key: String, _ defaults: UserDefaults) -> [SavedPlace] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedPlace].self, from: data) else { return [] }
        return list
    }
}
