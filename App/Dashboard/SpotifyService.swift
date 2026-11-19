// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spotify con su SDK oficial para iOS (App Remote). Requisitos de Spotify, que la app no puede
// saltarse:
//  - registrar una app en developer.spotify.com (la cuenta dueña necesita Premium desde 2026),
//    con la dirección de vuelta cfmotolink://spotify-login y el identificador io.github.cfmotolink.app;
//  - copiar su Client ID en MotoLink (no es una clave secreta);
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
    /// Canción que suena: las portadas que lleguen de otra se descartan.
    private var gate = ArtworkGate()
    private var artwork: CGImage?
    private var palette: ArtPalette?
    #else
    static let available = false
    #endif

    private var token: String?
    private var wanted = false
    /// Lo último publicado de Spotify (para volver a mostrarlo al elegir Spotify).
    private var lastSnapshot = MusicSnapshot()
    /// Reintentos seguidos tras un corte (se ponen a cero al conectar).
    private var retries = 0

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

    /// Abre la app de Spotify para que el usuario dé permiso. Spotify vuelve a MotoLink
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
        // Cadena vacía: Spotify sigue con lo último que sonaba (no elige música por su cuenta).
        r.authorizeAndPlayURI("") { [weak self] installed in
            guard !installed else { return }
            DispatchQueue.main.async {
                self?.phase = .failed("No se encontró la app de Spotify en este iPhone")
            }
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
        retries = 0
        phase = .connecting
        r.connect()
        #endif
    }

    func toggle() {
        #if canImport(SpotifyiOS)
        guard let api = remote?.playerAPI else {
            logLine("[SPOTIFY] no hay conexión para pausar o reanudar")
            return
        }
        if playing {
            api.pause { _, error in if let e = error { logLine("[SPOTIFY] no se pudo pausar: \(e.localizedDescription)") } }
        } else {
            api.resume { _, error in if let e = error { logLine("[SPOTIFY] no se pudo reanudar: \(e.localizedDescription)") } }
        }
        #endif
    }

    func next() {
        #if canImport(SpotifyiOS)
        remote?.playerAPI?.skip(toNext: { _, error in
            if let e = error { logLine("[SPOTIFY] no se pudo pasar a la siguiente: \(e.localizedDescription)") }
        })
        #endif
    }

    func previous() {
        #if canImport(SpotifyiOS)
        remote?.playerAPI?.skip(toPrevious: { _, error in
            if let e = error { logLine("[SPOTIFY] no se pudo volver a la anterior: \(e.localizedDescription)") }
        })
        #endif
    }

    /// Al elegir Spotify como servicio: la moto muestra enseguida lo que suena (o nada, si no
    /// está conectado), sin esperar a que cambie algo en el reproductor.
    func republish() {
        guard DashStore.shared.config.musicProvider == .spotify else { return }
        if connected && lastSnapshot.available {
            DashState.shared.setMusic(lastSnapshot)
        } else {
            DashState.shared.setMusic(MusicSnapshot())
        }
        #if canImport(SpotifyiOS)
        remote?.playerAPI?.getPlayerState { [weak self] result, _ in
            if let state = result as? SPTAppRemotePlayerState { self?.playerStateDidChange(state) }
        }
        #endif
    }

    private func publishEmpty() {
        title = ""
        artist = ""
        playing = false
        lastSnapshot = MusicSnapshot()
        #if canImport(SpotifyiOS)
        gate.reset()
        #endif
        if DashStore.shared.config.musicProvider == .spotify {
            DashState.shared.setMusic(MusicSnapshot())
        }
    }
}

#if canImport(SpotifyiOS)
extension SpotifyService: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        DispatchQueue.main.async {
            self.retries = 0
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
            logLine("[SPOTIFY] desconectado: \(error?.localizedDescription ?? "sin detalle")")
            guard self.wanted else { return }
            self.phase = .failed("Se cortó la conexión con Spotify; se reintenta al abrir la app")
            // Dos reintentos cortos (sirven si Spotify sigue sonando). Si iOS ya suspendió
            // Spotify o esta app, la conexión vuelve al abrir MotoLink.
            guard self.retries < 2, self.token != nil else { return }
            self.retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self = self, self.wanted, let r = self.remote, !r.isConnected else { return }
                self.phase = .connecting
                r.connect()
            }
        }
    }

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let track = playerState.track
        var m = MusicSnapshot()
        m.available = true
        m.source = "Spotify"
        m.title = track.name
        m.artist = track.artist.name
        m.album = track.album.name
        m.playing = !playerState.isPaused
        m.duration = Double(track.duration) / 1000
        m.position = Double(playerState.playbackPosition) / 1000
        m.positionTime = Date().timeIntervalSinceReferenceDate
        DispatchQueue.main.async {
            let uri = track.uri
            if self.gate.begin(uri) {
                // Canción nueva: fuera la portada y los colores de la anterior.
                self.artwork = nil
                self.palette = nil
                self.remote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 256, height: 256), callback: { [weak self] result, error in
                    let image = (result as? UIImage)?.cgImage
                    let colors = image.flatMap { ArtPalette.extract($0) }
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Si mientras llegaba ya sonaba otra canción, esta portada no sirve.
                        guard self.gate.accepts(uri) else {
                            logLine("[SPOTIFY] portada de una canción anterior descartada")
                            return
                        }
                        guard let image = image else {
                            logLine("[SPOTIFY] sin portada: \(error?.localizedDescription ?? "Spotify no la entregó")")
                            return
                        }
                        self.artwork = image
                        self.palette = colors
                        // Se completa lo último publicado de ESTA canción (no una copia vieja).
                        self.lastSnapshot.artwork = image
                        self.lastSnapshot.palette = colors
                        if DashStore.shared.config.musicProvider == .spotify {
                            DashState.shared.setMusic(self.lastSnapshot)
                        }
                    }
                })
            }
            m.artwork = self.artwork
            m.palette = self.palette
            let started = m.playing && !self.playing
            self.title = m.title
            self.artist = m.artist
            self.playing = m.playing
            self.lastSnapshot = m
            if DashStore.shared.config.musicProvider == .spotify {
                DashState.shared.setMusic(m)
                if started { DashStore.shared.musicStarted() }
            }
        }
    }
}
#endif
