// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

/// Tema de la app. "Noche" es una vista pensada para conducir de noche: negro puro, mapa
/// atenuado y acentos ámbar, que deslumbran menos que el azul.
enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
    case night

    var title: String {
        switch self {
        case .system: return "Automático"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        case .night: return "Noche"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

/// Colores resueltos para un tema. Los usan las tarjetas de SwiftUI, el mapa y la moto.
struct Palette: Equatable {
    let id: String
    let scheme: ColorScheme
    let card: Color
    let cardText: Color
    let secondaryText: Color
    let field: Color
    let accent: Color
    let onAccent: Color
    let banner: Color
    let bannerText: Color
    let danger: Color
    let warn: Color
    let mapStyle: UIUserInterfaceStyle
    let mutedMap: Bool
    let hud: HUDStyle
    let route: UIColor
    let routeCasing: UIColor
    let routeAlternate: UIColor

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private static func ui(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static let light = Palette(
        id: "light",
        scheme: .light,
        card: rgb(0xFFFFFF),
        cardText: rgb(0x0B1220),
        secondaryText: rgb(0x5A6678),
        field: rgb(0xEEF1F5),
        accent: rgb(0x1463E0),
        onAccent: rgb(0xFFFFFF),
        banner: rgb(0x0E1B2E),
        bannerText: rgb(0xFFFFFF),
        danger: rgb(0xD92D20),
        warn: rgb(0xD97A00),
        mapStyle: .light,
        mutedMap: false,
        hud: .day,
        route: ui(0x1463E0),
        routeCasing: ui(0x0A3A8C),
        routeAlternate: ui(0x8794A8)
    )

    static let dark = Palette(
        id: "dark",
        scheme: .dark,
        card: rgb(0x171C24),
        cardText: rgb(0xFFFFFF),
        secondaryText: rgb(0x9AA6B8),
        field: rgb(0x232A35),
        accent: rgb(0x3D8BFF),
        onAccent: rgb(0xFFFFFF),
        banner: rgb(0x0B1018),
        bannerText: rgb(0xFFFFFF),
        danger: rgb(0xFF5A4E),
        warn: rgb(0xFFB020),
        mapStyle: .dark,
        mutedMap: false,
        hud: .night,
        route: ui(0x4C9AFF),
        routeCasing: ui(0x0B2A5E),
        routeAlternate: ui(0x6B7686)
    )

    static let night = Palette(
        id: "night",
        scheme: .dark,
        card: rgb(0x000000),
        cardText: rgb(0xF4E9D6),
        secondaryText: rgb(0xA89B84),
        field: rgb(0x16130D),
        accent: rgb(0xFFB020),
        onAccent: rgb(0x000000),
        banner: rgb(0x000000),
        bannerText: rgb(0xFFE7B8),
        danger: rgb(0xFF6A5E),
        warn: rgb(0xFF8A3D),
        mapStyle: .dark,
        mutedMap: true,
        hud: .night,
        route: ui(0xFFB020),
        routeCasing: ui(0x4A3000),
        routeAlternate: ui(0x5E5E5E)
    )

    static func resolve(_ theme: AppTheme, system: ColorScheme) -> Palette {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .night: return .night
        case .system: return system == .dark ? .dark : .light
        }
    }
}
