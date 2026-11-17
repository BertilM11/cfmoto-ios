// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spotify con su SDK oficial para iOS (App Remote). Requisitos de Spotify, que la app no puede
// saltarse:
//  - registrar una app en developer.spotify.com (la cuenta dueña necesita Premium desde 2026),
//    con la dirección de vuelta cfmotolink://spotify-login y el identificador io.github.cfmotolink.app;
//  - copiar su Client ID en CFMoto Link (no es una clave secreta);
//  - tener la app de Spotify instalada y abierta.
// No se guarda ninguna credencial: el permiso que da Spotify dura una hora y vive en memoria.
import SwiftUI
import UIKit
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

final class SpotifyService: NSObject, ObservableObject {
    static let shared = SpotifyService()
    static let redirect = URL(string: "cfmotolink://spotify-login")!

    enum Phase: Equatable {
        case off
        case authorizing
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var playing = false

    #if canImport(SpotifyiOS)
    static let available = true
    private var remote: SPTAppRemote?
    private var lastTrack = ""
    private var artwork: CGImage?
    #else
    static let available = false
    #endif

    private var token: String?
    private var wanted = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.appBecameActive() }
    }

    var connected: Bool { phase == .connected }

    var statusText: String {
        switch phase {
        case .off: return "Sin conectar"
        case .authorizing: return "Esperando el permiso en la app de Spotify…"
        case .connecting: return "Conectando con Spotify…"
        case .connected: return "Conectado"
        case .failed(let why): return why
        }
    }

    /// Abre la app de Spotify para que el usuario dé permiso. Spotify vuelve a CFMoto Link
    /// con un permiso temporal.
    func connect(clientID: String) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            phase = .failed("Falta el Client ID de tu app de Spotify")
            return
        }
        #if canImport(SpotifyiOS)
        wanted = true
        let configuration = SPTConfiguration(clientID: id, redirectURL: SpotifyService.redirect)
        let r = SPTAppRemote(configuration: configuration, logLevel: .error)
        r.delegate = self
        remote = r
        if let token = token {
            r.connectionParameters.accessToken = token
            phase = .connecting
            r.connect()
            return
        }
        phase = .authorizing
        if !r.authorizeAndPlayURI("") {
            phase = .failed("No se encontró la app de Spotify en este iPhone")
        }
        logLine("[SPOTIFY] pidiendo permiso a la app de Spotify")
        #else
        phase = .failed("Esta compilación no incluye el SDK de Spotify")
        #endif
    }

    /// Vuelta desde la app de Spotify (cfmotolink://spotify-login…).
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == SpotifyService.redirect.scheme else { return false }
        #if canImport(SpotifyiOS)
        guard let r = remote else { return true }
        let params = r.authorizationParameters(from: url)
        if let t = params?[SPTAppRemoteAccessTokenKey] {
            token = t
            r.connectionParameters.accessToken = t
            phase = .connecting
            r.connect()
        } else if let error = params?[SPTAppRemoteErrorDescriptionKey] {
            phase = .failed("Spotify no dio permiso: \(error)")
            logLine("[SPOTIFY] permiso denegado: \(error)")
        }
        #endif
        return true
    }

    func disconnect() {
        wanted = false
        #if canImport(SpotifyiOS)
        if remote?.isConnected == true { remote?.disconnect() }
        #endif
        phase = .off
        publishEmpty()
    }

    /// Al volver la app al frente, se reconecta si se había perdido la conexión.
    func appBecameActive() {
        #if canImport(SpotifyiOS)
        guard wanted, let r = remote, !r.isConnected, token != nil else { return }
        phase = .connecting
        r.connect()
        #endif
    }

    func toggle() {
        #if canImport(SpotifyiOS)
        if playing { remote?.playerAPI?.pause(nil) } else { remote?.playerAPI?.resume(nil) }
        #endif
    }

    func next() {
        #if canImport(SpotifyiOS)
        remote?.playerAPI?.skip(toNext: nil)
        #endif
    }

    func previous() {
        #if canImport(SpotifyiOS)
        remote?.playerAPI?.skip(toPrevious: nil)
        #endif
    }

    private func publishEmpty() {
        title = ""
        artist = ""
        playing = false
        if DashStore.shared.config.musicProvider == .spotify {
            DashState.shared.setMusic(MusicSnapshot())
        }
    }
}

#if canImport(SpotifyiOS)
extension SpotifyService: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        DispatchQueue.main.async {
            self.phase = .connected
            logLine("[SPOTIFY] conectado con la app de Spotify")
        }
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
            if let error = error { logLine("[SPOTIFY] no se pudo leer la canción: \(error.localizedDescription)") }
        })
        appRemote.playerAPI?.getPlayerState({ [weak self] result, _ in
            if let state = result as? SPTAppRemotePlayerState { self?.playerStateDidChange(state) }
        })
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        DispatchQueue.main.async {
            let why = error?.localizedDescription ?? "error desconocido"
            self.phase = .failed("No se pudo conectar: abre Spotify y vuelve a intentarlo (\(why))")
            logLine("[SPOTIFY] fallo al conectar: \(why)")
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        DispatchQueue.main.async {
            if self.wanted {
                self.phase = .failed("Se cortó la conexión con Spotify; se reintenta al abrir la app")
            }
            logLine("[SPOTIFY] desconectado: \(error?.localizedDescription ?? "sin detalle")")
        }
    }

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let track = playerState.track
        var m = MusicSnapshot()
        m.available = true
        m.source = "Spotify"
        m.title = track.name
        m.artist = track.artist.name
        m.playing = !playerState.isPaused
        m.duration = Double(track.duration) / 1000
        m.position = Double(playerState.playbackPosition) / 1000
        m.positionTime = Date().timeIntervalSinceReferenceDate
        DispatchQueue.main.async {
            let newTrack = track.uri != self.lastTrack
            if newTrack {
                self.lastTrack = track.uri
                self.artwork = nil
                self.remote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 256, height: 256), callback: { [weak self] result, _ in
                    guard let self = self, let image = (result as? UIImage)?.cgImage else { return }
                    DispatchQueue.main.async {
                        self.artwork = image
                        if DashStore.shared.config.musicProvider == .spotify {
                            var withArt = m
                            withArt.artwork = image
                            DashState.shared.setMusic(withArt)
                        }
                    }
                })
            }
            m.artwork = self.artwork
            let started = m.playing && !self.playing
            self.title = m.title
            self.artist = m.artist
            self.playing = m.playing
            if DashStore.shared.config.musicProvider == .spotify {
                DashState.shared.setMusic(m)
                if started { DashStore.shared.musicStarted() }
            }
        }
    }
}
#endif
