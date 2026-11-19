// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO

/// 0.7.1: el emblema de BERL (la marca del autor) para la pantalla de la moto. Va dentro del
/// código (PNG en gris, 79×54) para dibujarse igual en la app, en la extensión y en las
/// pruebas. Se usa como máscara: se pinta con el color tenue de «© OpenStreetMap».
enum BrandMark {
    static let mask: CGImage? = {
        guard let data = Data(base64Encoded: parts.joined()),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }()

    /// Ancho del emblema para un alto dado.
    static func width(forHeight h: CGFloat) -> CGFloat {
        guard let m = mask, m.height > 0 else { return 0 }
        return h * CGFloat(m.width) / CGFloat(m.height)
    }

    private static let parts: [String] = [
        "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",
    ]
}
