// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Apariencia del panel: día o noche según el sol, y colores de la tarjeta de música sacados
// de la portada. Sin UIKit: lo usan la app, la vista previa y las pruebas en macOS.
import Foundation
import CoreGraphics

// MARK: - Día y noche

enum SunClock {
    /// Amanecer y atardecer del día solar que corresponde a `date` en esa posición
    /// (ecuación del amanecer, precisión de un par de minutos). nil en días sin amanecer o
    /// sin atardecer (zonas polares).
    static func times(on date: Date, lat: Double, lon: Double) -> (sunrise: Date, sunset: Date)? {
        let rad = Double.pi / 180
        let julian = date.timeIntervalSince1970 / 86400 + 2_440_587.5
        // Día solar local: el mediodía solar más cercano a `date`. (Redondear hacia arriba en
        // hora UTC daba, en América, el amanecer de mañana durante casi todo el día y el panel
        // se quedaba en modo noche.)
        let n = (julian - 2_451_545.0 + 0.0008 + lon / 360).rounded()
        let meanSolar = n - lon / 360
        let m = (357.5291 + 0.98560028 * meanSolar).truncatingRemainder(dividingBy: 360)
        let c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2_451_545.0 + meanSolar + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        let sinDecl = sin(lambda * rad) * sin(23.4397 * rad)
        let cosDecl = cos(asin(sinDecl))
        let cosHour = (sin(-0.833 * rad) - sin(lat * rad) * sinDecl) / (cos(lat * rad) * cosDecl)
        guard cosHour >= -1, cosHour <= 1 else { return nil }
        let hour = acos(cosHour) / rad
        func toDate(_ j: Double) -> Date { Date(timeIntervalSince1970: (j - 2_440_587.5) * 86400) }
        return (toDate(transit - hour / 360), toDate(transit + hour / 360))
    }

    /// true de noche, false de día. nil si no se puede calcular (sin posición o zona polar).
    static func isNight(at date: Date, lat: Double, lon: Double) -> Bool? {
        guard let t = times(on: date, lat: lat, lon: lon) else { return nil }
        return date < t.sunrise || date > t.sunset
    }

    /// Sin posición: de 18:30 a 5:30 (hora local) se considera noche.
    static func isNightByClock(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        return minutes >= 18 * 60 + 30 || minutes < 5 * 60 + 30
    }
}

// MARK: - Colores

struct RGB: Equatable, Codable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    var cg: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }

    /// Luminancia relativa (WCAG).
    var luminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Relación de contraste WCAG entre dos colores (1 a 21).
    func contrast(with o: RGB) -> Double {
        let a = luminance
        let b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func mixed(with o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    /// Matiz (0…360), saturación y luminosidad (0…1).
    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx - mn > 1e-6 else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    init(h: Double, s: Double, l: Double) {
        let s = min(1, max(0, s))
        let l = min(1, max(0, l))
        guard s > 1e-6 else {
            self.init(l, l, l)
            return
        }
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1 / 2.0 { return q }
            if t < 2 / 3.0 { return p + (q - p) * (2 / 3.0 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        self.init(hue(p, q, hh + 1 / 3.0), hue(p, q, hh), hue(p, q, hh - 1 / 3.0))
    }

    /// Diferencia entre el canal más alto y el más bajo (0: gris puro).
    var chroma: Double { max(r, g, b) - min(r, g, b) }

    func with(s: Double? = nil, l: Double? = nil) -> RGB {
        let x = hsl
        return RGB(h: x.h, s: s ?? x.s, l: l ?? x.l)
    }
}

/// Colores dominantes de una portada.
struct ArtPalette: Equatable {
    var base: RGB
    var accent: RGB

    /// Analiza la portada reducida a 32×32. La imagen original no se toca.
    static func extract(_ image: CGImage) -> ArtPalette? {
        let side = 32
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        struct Bin {
            var count = 0.0
            var r = 0.0
            var g = 0.0
            var b = 0.0
        }
        var bins: [Int: Bin] = [:]
        for i in stride(from: 0, to: data.count, by: 4) {
            let a = Double(data[i + 3]) / 255
            guard a > 0.5 else { continue }
            let r = Double(data[i]) / 255 / a
            let g = Double(data[i + 1]) / 255 / a
            let b = Double(data[i + 2]) / 255 / a
            let key = (Int(min(255, r * 255)) >> 5) << 6 | (Int(min(255, g * 255)) >> 5) << 3 | (Int(min(255, b * 255)) >> 5)
            var bin = bins[key] ?? Bin()
            bin.count += 1
            bin.r += r
            bin.g += g
            bin.b += b
            bins[key] = bin
        }
        guard !bins.isEmpty else { return nil }
        let colors: [(RGB, Double)] = bins.values.map { b in
            (RGB(b.r / b.count, b.g / b.count, b.b / b.count), b.count)
        }
        // Peso: frecuencia, con preferencia por los colores con color (no grises puros).
        func score(_ c: RGB, _ n: Double) -> Double {
            let x = c.hsl
            let extreme = x.l < 0.08 || x.l > 0.94
            return n * (0.35 + x.s) * (extreme ? 0.35 : 1)
        }
        let sorted = colors.sorted { score($0.0, $0.1) > score($1.0, $1.1) }
        let base = sorted[0].0
        let bh = base.hsl
        var accent = base.with(l: bh.l > 0.5 ? bh.l - 0.25 : bh.l + 0.25)
        for (c, _) in sorted.dropFirst() {
            let x = c.hsl
            var dh = abs(x.h - bh.h)
            if dh > 180 { dh = 360 - dh }
            if (dh > 35 && x.s > 0.2) || abs(x.l - bh.l) > 0.35 {
                accent = c
                break
            }
        }
        return ArtPalette(base: base, accent: accent)
    }
}

/// Estilo de la tarjeta de música.
enum MusicCardStyle: String, Codable, CaseIterable, Identifiable {
    case dynamic, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dynamic: return "Colores de la portada"
        case .dark: return "Fondo oscuro fijo"
        case .light: return "Fondo claro fijo"
        }
    }
}

/// Colores finales de la tarjeta de música, ya con contraste comprobado.
struct MusicCardColors: Equatable {
    var top: RGB
    var bottom: RGB
    var text: RGB
    var secondary: RGB
    var accent: RGB
    var track: RGB

    /// `spotify`: con música de Spotify el fondo oscuro neutro es el color de Spotify (#191414),
    /// como piden sus reglas cuando no se usan los colores de la portada.
    static func make(style: MusicCardStyle, palette: ArtPalette?, night: Bool, intensity: Double, spotify: Bool = false) -> MusicCardColors {
        let neutralDark = spotify ? (top: RGB(hex: 0x191414), bottom: RGB(hex: 0x121212)) : (top: RGB(hex: 0x141B26), bottom: RGB(hex: 0x0B1018))
        let neutralLight = (top: RGB(hex: 0xF7F8FA), bottom: RGB(hex: 0xE6EAF0))
        var top: RGB
        var bottom: RGB
        var accentSource: RGB?
        let darkCard: Bool
        switch style {
        case .dark:
            (top, bottom) = neutralDark
            darkCard = true
        case .light:
            (top, bottom) = neutralLight
            darkCard = false
        case .dynamic:
            darkCard = night
            let neutral = night ? neutralDark : neutralLight
            if let p = palette {
                let x = p.base.hsl
                // Tonos sobrios: saturación limitada y luminosidad según el tema.
                let s = min(x.s, 0.55)
                let t0 = night ? RGB(h: x.h, s: s, l: 0.30) : RGB(h: x.h, s: s * 0.8, l: 0.84)
                let t1 = night ? RGB(h: x.h, s: s, l: 0.13) : RGB(h: x.h, s: s * 0.8, l: 0.72)
                let k = min(1, max(0, intensity))
                top = neutral.top.mixed(with: t0, k)
                bottom = neutral.bottom.mixed(with: t1, k)
                accentSource = p.accent
            } else {
                (top, bottom) = neutral
            }
        }
        let mid = top.mixed(with: bottom, 0.5)
        let white = RGB(1, 1, 1)
        let ink = RGB(hex: 0x0B1220)
        // El texto se elige por contraste con el fondo real (mínimo 4,5:1).
        var text = darkCard ? white : ink
        if min(text.contrast(with: top), text.contrast(with: bottom)) < 4.5 {
            let other = darkCard ? ink : white
            if min(other.contrast(with: top), other.contrast(with: bottom)) > min(text.contrast(with: top), text.contrast(with: bottom)) {
                text = other
            }
        }
        var secondary = text.mixed(with: mid, 0.32)
        if secondary.contrast(with: mid) < 3.2 { secondary = text.mixed(with: mid, 0.15) }
        var accent = accentSource ?? (darkCard ? RGB(hex: 0x4C9AFF) : RGB(hex: 0x1463E0))
        // El acento (barra de progreso) también tiene que verse sobre el fondo.
        var tries = 0
        while accent.contrast(with: mid) < 3, tries < 12 {
            let l = accent.hsl.l
            accent = accent.with(l: mid.luminance < 0.4 ? min(1, l + 0.07) : max(0, l - 0.07))
            tries += 1
        }
        if accent.contrast(with: mid) < 3 { accent = text }
        let track = text.mixed(with: mid, 0.7)
        return MusicCardColors(top: top, bottom: bottom, text: text, secondary: secondary, accent: accent, track: track)
    }

    func mixed(with o: MusicCardColors, _ t: Double) -> MusicCardColors {
        MusicCardColors(
            top: top.mixed(with: o.top, t), bottom: bottom.mixed(with: o.bottom, t), text: text.mixed(with: o.text, t),
            secondary: secondary.mixed(with: o.secondary, t), accent: accent.mixed(with: o.accent, t), track: track.mixed(with: o.track, t)
        )
    }
}

/// Grosor y contraste de la línea de la ruta.
enum RouteStyle: String, Codable, CaseIterable, Identifiable {
    case standard, highContrast, thin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Normal"
        case .highContrast: return "Alto contraste"
        case .thin: return "Fina"
        }
    }
}

enum ArtworkSize: String, Codable, CaseIterable, Identifiable {
    case small, normal, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return "Pequeña"
        case .normal: return "Normal"
        case .large: return "Grande"
        }
    }
    /// Parte del alto disponible que ocupa la portada en la tarjeta grande.
    var fraction: CGFloat {
        switch self {
        case .small: return 0.62
        case .normal: return 0.82
        case .large: return 1
        }
    }
}
