// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreVideo

/// Origen de la imagen que se envía a la moto: la imagen de prueba (app) o la pantalla del
/// iPhone (extensión de transmisión). Entrega fotogramas BGRA del tamaño pedido a `sink`.
protocol FrameSource: AnyObject {
    func start()
    func stop()
}

typealias FrameSourceFactory = (_ width: Int, _ height: Int, _ fps: Int, _ sink: @escaping (CVPixelBuffer) -> Void) -> FrameSource
