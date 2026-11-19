// SPDX-License-Identifier: AGPL-3.0-or-later
import ReplayKit
import CoreMedia
import ImageIO

/// Extensión "Transmitir pantalla": iOS le entrega la pantalla del iPhone mientras la
/// transmisión está activa, aunque la app MotoLink esté cerrada. Toda la conexión con la
/// moto vive aquí.
final class SampleHandler: RPBroadcastSampleHandler {
    private let link = BikeLink()
    private var logServer: LogServer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        LogBus.shared.clear()
        ScreenFeed.shared.reset()
        logServer = LogServer()
        logLine("[TRANSMISIÓN] iniciada: la pantalla del iPhone irá a la moto")

        link.role = "transmisión"
        link.sourceFactory = { w, h, fps, sink in
            ScreenSource(width: w, height: h, fps: fps, sink: sink)
        }
        link.onStatus = { s in
            logLine("[estado] \(s)")
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if !self.link.start(manualBikeIp: "") {
                let reason = "No se pudo conectar con la moto. Conéctate al Wi-Fi DIRECT-…-CFMOTO, cierra la prueba en la app y vuelve a intentarlo."
                logLine("[TRANSMISIÓN] !! \(reason)")
                self.finishBroadcastWithError(NSError(
                    domain: "CFMotoLink", code: 1,
                    userInfo: [NSLocalizedFailureReasonErrorKey: reason, NSLocalizedDescriptionKey: reason]
                ))
            }
        }
    }

    override func broadcastPaused() {
        logLine("[TRANSMISIÓN] en pausa")
    }

    override func broadcastResumed() {
        logLine("[TRANSMISIÓN] reanudada")
    }

    override func broadcastFinished() {
        logLine("[TRANSMISIÓN] terminada")
        link.stop()
        logServer?.close()
        logServer = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var orientation = CGImagePropertyOrientation.up
        if let n = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let o = CGImagePropertyOrientation(rawValue: n.uint32Value) {
            orientation = o
        }
        ScreenFeed.shared.update(buffer, orientation)
    }
}
