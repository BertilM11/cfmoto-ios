// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spotify con su SDK oficial para iOS (App Remote). Requisitos de Spotify, que la app no puede
// saltarse:
//  - registrar una app en developer.spotify.com (la cuenta dueña necesita Premium desde 2026),
//    con la dirección de vuelta cfmotolink://spotify-login y el identificador io.github.cfmotolink.app;
//  - copiar su Client ID en MotoLink (no es una clave secreta);
//  - tener la app de Spotify instalada y abierta.
// No se guarda ninguna credencial: el permiso que da Spotify dura una hora y vive en memoria.
import AVFoundation
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
    /// 0.9.0: vigilancia de la conexión. Cuando Spotify se pausa (o entra una llamada), iOS lo
    /// duerme y la conexión se corta; al volver a sonar hay que reconectar sin esperar a que se
    /// abra MotoLink. Cada 3 s, mientras se quiera Spotify y no haya conexión: se reintenta en
    /// cuanto iOS dice que otra app está sonando, y si no, cada vez más espaciado (5 s → 30 s).
    private var watchdog: Timer?
    private var lastAttempt = Date.distantPast
    private var lostAt: Date?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.appBecameActive() }
        // iOS avisa cuando otra app (Spotify) empieza o deja de sonar.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            if raw == AVAudioSession.SilenceSecondaryAudioHintType.begin.rawValue {
                self?.reconnectSoon(reason: "otra app empezó a sonar")
            }
        }
    }

    /// Espera antes del siguiente intento, según cuánto lleva cortada la conexión.
    static func retryDelay(sinceLost: TimeInterval) -> TimeInterval {
        if sinceLost < 30 { return 5 }
        if sinceLost < 120 { return 10 }
        if sinceLost < 600 { return 20 }
        return 30
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func tick() {
        #if canImport(SpotifyiOS)
        guard wanted, token != nil, let r = remote else {
            stopWatchdog()
            return
        }
        if r.isConnected {
            stopWatchdog()
            return
        }
        let now = Date()
        let lost = lostAt ?? now
        let otherAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying
        let wait = otherAudio ? 4 : SpotifyService.retryDelay(sinceLost: now.timeIntervalSince(lost))
        guard now.timeIntervalSince(lastAttempt) >= wait else { return }
        attempt(r, reason: otherAudio ? "Spotify está sonando" : "reintento")
        #endif
    }

    /// Reintenta ya (si no se acaba de intentar).
    private func reconnectSoon(reason: String) {
        #if canImport(SpotifyiOS)
        guard wanted, token != nil, let r = remote, !r.isConnected else { return }
        guard Date().timeIntervalSince(lastAttempt) >= 2 else { return }
        attempt(r, reason: reason)
        #endif
    }

    #if canImport(SpotifyiOS)
    private func attempt(_ r: SPTAppRemote, reason: String) {
        lastAttempt = Date()
        phase = .connecting
        if reason != "reintento" { logLine("[SPOTIFY] reconectando (\(reason))") }
        r.connect()
    }
    #endif

    /// Lo que muestra la moto mientras no hay conexión: la última canción, en pausa (sin un
    /// tiempo que avanza ni una canción que ya no suena) y avisando que se está reconectando.
    private func publishStale() {
        guard lastSnapshot.available else { return }
        var m = lastSnapshot
        if m.playing {
            m.position = min(m.duration, m.position + max(0, Date().timeIntervalSinceReferenceDate - m.positionTime))
        }
        m.positionTime = Date().timeIntervalSinceReferenceDate
        m.playing = false
        m.source = "Spotify · reconectando"
        lastSnapshot = m
        playing = false
        if DashStore.shared.config.musicProvider == .spotify {
            DashState.shared.setMusic(m)
        }
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
        guard url.scheme == SpotifyService.redirect.scheme, url.host == SpotifyService.redirect.host else { return false }
        #if canImport(SpotifyiOS)
        // Solo se acepta la vuelta que MotoLink pidió: otra app no puede colar un permiso ajeno.
        guard let r = remote, phase == .authorizing else { return true }
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
        stopWatchdog()
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
        attempt(r, reason: "MotoLink volvió al frente")
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
            if let lost = self.lostAt {
                logLine(String(format: "[SPOTIFY] reconectado tras %.0f s sin conexión", Date().timeIntervalSince(lost)))
            } else {
                logLine("[SPOTIFY] conectado con la app de Spotify")
            }
            self.lostAt = nil
            self.stopWatchdog()
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
            // Mientras se reintenta solo se anota el primer fallo (no uno cada pocos segundos).
            if self.lostAt == nil || self.watchdog == nil { logLine("[SPOTIFY] fallo al conectar: \(why)") }
            // Se sigue intentando mientras se quiera Spotify (no solo al abrir MotoLink).
            if self.wanted && self.token != nil {
                if self.lostAt == nil { self.lostAt = Date() }
                self.startWatchdog()
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        DispatchQueue.main.async {
            logLine("[SPOTIFY] desconectado: \(error?.localizedDescription ?? "sin detalle")")
            guard self.wanted else { return }
            self.phase = .failed("Se cortó la conexión con Spotify; se reintenta en cuanto vuelva a sonar")
            self.lostAt = Date()
            self.publishStale()
            self.startWatchdog()
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
