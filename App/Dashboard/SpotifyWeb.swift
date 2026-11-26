// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.9.1: Spotify por internet (Web API), para cuando la conexión local (App Remote) no está.
// La conexión local se corta cuando Spotify se pausa y solo se puede volver a abrir con la app
// de Spotify en pantalla; con el iPhone bloqueado era imposible. Por internet, MotoLink pregunta
// cada 2 s (4 s en pausa) qué suena (título, artista, portada, posición) y puede pausar, reanudar o cambiar de
// canción (esto último exige Spotify Premium).
//
// Seguridad:
//  - inicio de sesión con PKCE (sin clave secreta en la app); el Client ID no es secreto;
//  - el permiso de larga duración (refresh token) se guarda solo en el llavero del iPhone,
//    nunca en archivos, en el registro ni en el repositorio; el de una hora vive en memoria;
//  - permisos mínimos: leer lo que suena y controlar la reproducción;
//  - «Desconectar» borra el permiso del llavero.
// Requisito en developer.spotify.com › tu app › Settings: marcar «Web API» y agregar la
// dirección de vuelta cfmotolink://spotify-web.
import AuthenticationServices
import CryptoKit
import Security
import UIKit

final class SpotifyWeb: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyWeb()
    static let redirect = "cfmotolink://spotify-web"
    static let scopes = "user-read-playback-state user-read-currently-playing user-modify-playback-state"

    enum Phase: Equatable {
        case off
        case signingIn
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .off
    /// true mientras MotoLink está leyendo Spotify por internet (sin conexión local).
    @Published private(set) var polling = false

    private var accessToken: String?
    private var expires = Date.distantPast
    private var timer: Timer?
    private var inFlight = false
    private var backoffUntil = Date.distantPast
    private var lastArtURL: String?
    private var artwork: CGImage?
    private var palette: ArtPalette?
    private var session: ASWebAuthenticationSession?
    private var lastTrackURI = ""
    private var lastPlaying = false
    private let http: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Si hay sesión guardada (se lee del llavero una vez y se actualiza al guardar o borrar).
    private var stored: Bool?
    var signedIn: Bool {
        if let s = stored { return s }
        let s = Keychain.read(SpotifyWeb.keychainKey) != nil
        stored = s
        return s
    }

    var statusText: String {
        switch phase {
        case .off: return signedIn ? "Listo (se usa cuando la conexión local no está)" : "Sin iniciar sesión"
        case .signingIn: return "Iniciando sesión en Spotify…"
        case .ready: return polling ? "Leyendo Spotify por internet" : "Listo (se usa cuando la conexión local no está)"
        case .failed(let why): return why
        }
    }

    private static let keychainKey = "spotify.web.refresh"

    // MARK: - Ciclo

    /// Se llama una vez al abrir la app.
    func start() {
        guard timer == nil else { return }
        if signedIn { phase = .ready }
        // 0.9.3: se revisa cada segundo; se pregunta cada 2 s mientras suena (4 s en pausa) y justo
        // al terminar la canción, para que el cambio de canción salga sin retraso.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Solo se lee por internet si: Spotify es el servicio elegido, hay sesión iniciada, la
    /// conexión local no está, y la moto está conectada o MotoLink está en pantalla (para no
    /// gastar datos con la app olvidada en segundo plano).
    private var shouldPoll: Bool {
        guard signedIn, DashStore.shared.config.musicProvider == .spotify else { return false }
        guard !SpotifyService.shared.connected else { return false }
        return NavEngine.shared.linkActive || UIApplication.shared.applicationState == .active
    }

    private func tick() {
        let want = shouldPoll
        if want != polling {
            polling = want
            logLine(want ? "[SPOTIFY] leyendo Spotify por internet (sin conexión local)" : "[SPOTIFY] dejo de leer Spotify por internet")
        }
        guard want, !inFlight, Date() >= backoffUntil else { return }
        let now = Date()
        let gap: TimeInterval = lastPlaying ? 2 : 4
        let ended = trackEnd.map { now >= $0 } ?? false
        guard ended || now.timeIntervalSince(lastPoll) >= gap else { return }
        poll()
    }

    /// 0.9.3: hora de la última pregunta y hora en que termina la canción que suena.
    private var lastPoll = Date.distantPast
    private var trackEnd: Date?

    // MARK: - Inicio de sesión (PKCE)

    func signIn(clientID: String) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            phase = .failed("Falta el Client ID de tu app de Spotify")
            return
        }
        let verifier = SpotifyWeb.randomString(64)
        let challenge = SpotifyWeb.challenge(for: verifier)
        let state = SpotifyWeb.randomString(16)
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyWeb.redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: SpotifyWeb.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = c.url else { return }
        phase = .signingIn
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "cfmotolink") { [weak self] callback, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.session = nil
                guard let cb = callback, let items = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems else {
                    self.phase = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                        ? (self.signedIn ? .ready : .off) : .failed("No se pudo iniciar sesión en Spotify")
                    return
                }
                // Solo se acepta la vuelta de ESTE inicio de sesión.
                guard cb.host == "spotify-web", items.first(where: { $0.name == "state" })?.value == state else {
                    self.phase = .failed("Respuesta de Spotify no válida")
                    return
                }
                if let err = items.first(where: { $0.name == "error" })?.value {
                    self.phase = .failed("Spotify no dio permiso (\(err))")
                    return
                }
                guard let code = items.first(where: { $0.name == "code" })?.value else {
                    self.phase = .failed("Spotify no devolvió el permiso")
                    return
                }
                self.exchange(code: code, verifier: verifier, clientID: id)
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    func signOut() {
        Keychain.delete(SpotifyWeb.keychainKey)
        Keychain.delete(SpotifyWeb.keychainKey + ".client")
        stored = false
        accessToken = nil
        phase = .off
        polling = false
        logLine("[SPOTIFY] sesión por internet cerrada (permiso borrado del llavero)")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func exchange(code: String, verifier: String, clientID: String) {
        tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyWeb.redirect,
            "client_id": clientID,
            "code_verifier": verifier,
        ], clientID: clientID) { [weak self] ok in
            guard let self = self else { return }
            self.phase = ok ? .ready : .failed("Spotify no aceptó el inicio de sesión")
            if ok { logLine("[SPOTIFY] sesión por internet iniciada") }
        }
    }

    /// Pide un permiso de una hora con el de larga duración guardado.
    private func refresh(_ done: @escaping (Bool) -> Void) {
        guard let refresh = Keychain.read(SpotifyWeb.keychainKey),
              let clientID = Keychain.read(SpotifyWeb.keychainKey + ".client") else {
            done(false)
            return
        }
        tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID], clientID: clientID, done)
    }

    private func tokenRequest(_ form: [String: String], clientID: String, _ done: @escaping (Bool) -> Void) {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = SpotifyWeb.formBody(form).data(using: .utf8)
        http.dataTask(with: req) { [weak self] data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard code == 200, let token = obj?["access_token"] as? String else {
                    if code == 400 || code == 401 {
                        // Permiso revocado o vencido: hay que volver a iniciar sesión.
                        Keychain.delete(SpotifyWeb.keychainKey)
                        self.stored = false
                        self.phase = .failed("Vuelve a iniciar sesión en Spotify (el permiso ya no es válido)")
                        logLine("[SPOTIFY] el permiso por internet ya no es válido (código \(code))")
                    }
                    done(false)
                    return
                }
                self.accessToken = token
                let secs = (obj?["expires_in"] as? Double) ?? 3600
                self.expires = Date().addingTimeInterval(secs - 60)
                if let r = obj?["refresh_token"] as? String {
                    Keychain.save(r, for: SpotifyWeb.keychainKey)
                    Keychain.save(clientID, for: SpotifyWeb.keychainKey + ".client")
                    self.stored = true
                }
                done(true)
            }
        }.resume()
    }

    /// Ejecuta `work` con un permiso vigente.
    private func withToken(_ work: @escaping (String) -> Void) {
        if let t = accessToken, Date() < expires {
            work(t)
            return
        }
        refresh { [weak self] ok in
            guard ok, let t = self?.accessToken else { return }
            work(t)
        }
    }

    // MARK: - Lo que suena

    private func poll() {
        inFlight = true
        lastPoll = Date()
        trackEnd = nil
        withToken { [weak self] token in
            guard let self = self else { return }
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player?additional_types=episode")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            self.http.dataTask(with: req) { data, response, _ in
                let http = response as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                DispatchQueue.main.async {
                    self.inFlight = false
                    switch code {
                    case 200:
                        if let data = data, let p = SpotifyWeb.parsePlayer(data) { self.publish(p) }
                    case 204:
                        // Spotify no está reproduciendo en ningún dispositivo.
                        self.publishIdle()
                    case 401:
                        self.accessToken = nil
                    case 429:
                        let wait = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
                        self.backoffUntil = Date().addingTimeInterval(min(120, max(4, wait)))
                        logLine("[SPOTIFY] Spotify pide esperar \(Int(wait)) s antes de volver a preguntar")
                    default:
                        break
                    }
                }
            }.resume()
        }
        // Si no hubo permiso (sin red), se libera para el siguiente intento.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.inFlight = false }
    }

    struct Player: Equatable {
        var title: String
        var artist: String
        var album: String
        var uri: String
        var playing: Bool
        var position: Double
        var duration: Double
        var artURL: String?
    }

    static func parsePlayer(_ data: Data) -> Player? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = obj["item"] as? [String: Any] else { return nil }
        let title = item["name"] as? String ?? ""
        var artist = ((item["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        var album = ""
        var images: [[String: Any]] = []
        if let a = item["album"] as? [String: Any] {
            album = a["name"] as? String ?? ""
            images = a["images"] as? [[String: Any]] ?? []
        } else if let show = item["show"] as? [String: Any] {
            // Pódcast: el «artista» es el programa.
            artist = show["name"] as? String ?? artist
            images = item["images"] as? [[String: Any]] ?? []
        }
        // La portada más cercana a 300 px.
        let art = images.min { a, b in
            abs(((a["width"] as? Int) ?? 0) - 300) < abs(((b["width"] as? Int) ?? 0) - 300)
        }?["url"] as? String
        return Player(title: title, artist: artist, album: album, uri: item["uri"] as? String ?? title,
                      playing: obj["is_playing"] as? Bool ?? false,
                      position: Double(obj["progress_ms"] as? Int ?? 0) / 1000,
                      duration: Double(item["duration_ms"] as? Int ?? 0) / 1000,
                      artURL: art)
    }

    private func publish(_ p: Player) {
        if p.uri != lastTrackURI {
            lastTrackURI = p.uri
            if p.artURL != lastArtURL {
                artwork = nil
                palette = nil
            }
        }
        if let url = p.artURL, url != lastArtURL {
            lastArtURL = url
            fetchArt(url)
        }
        var m = MusicSnapshot()
        m.available = true
        m.source = "Spotify"
        m.title = p.title
        m.artist = p.artist
        m.album = p.album
        m.playing = p.playing
        m.duration = p.duration
        m.position = p.position
        m.positionTime = Date().timeIntervalSinceReferenceDate
        m.artwork = artwork
        m.palette = palette
        trackEnd = p.playing && p.duration > 0 ? Date().addingTimeInterval(max(0.5, p.duration - p.position + 0.4)) : nil
        let started = p.playing && !lastPlaying
        lastPlaying = p.playing
        SpotifyService.shared.adoptFromWeb(m, started: started)
    }

    private func publishIdle() {
        guard lastPlaying else { return }
        lastPlaying = false
        SpotifyService.shared.pausedFromWeb()
    }

    private func fetchArt(_ url: String) {
        guard let u = URL(string: url), u.host?.hasSuffix("scdn.co") == true else { return }
        http.dataTask(with: u) { [weak self] data, _, _ in
            let image = data.flatMap { UIImage(data: $0)?.cgImage }
            let colors = image.flatMap { ArtPalette.extract($0) }
            DispatchQueue.main.async {
                guard let self = self, self.lastArtURL == url, let image = image else { return }
                self.artwork = image
                self.palette = colors
                SpotifyService.shared.artworkFromWeb(image, colors)
            }
        }.resume()
    }

    // MARK: - Controles (Spotify Premium)

    func control(_ action: String) {
        let (method, path): (String, String)
        switch action {
        case "pause": (method, path) = ("PUT", "pause")
        case "play": (method, path) = ("PUT", "play")
        case "next": (method, path) = ("POST", "next")
        default: (method, path) = ("POST", "previous")
        }
        withToken { [weak self] token in
            guard let self = self else { return }
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(path)")!)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            self.http.dataTask(with: req) { _, response, _ in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    if code >= 300 {
                        logLine("[SPOTIFY] Spotify no hizo «\(action)» por internet (código \(code)\(code == 403 ? ": requiere Premium" : ""))")
                    }
                    // Se vuelve a preguntar enseguida para que la moto muestre el cambio.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if !self.inFlight { self.poll() } }
                }
            }.resume()
        }
    }

    // MARK: - Ayudas

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formBody(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }
}

/// Llavero del iPhone (solo este dispositivo, disponible tras el primer desbloqueo para que
/// funcione con el iPhone bloqueado en la moto).
enum Keychain {
    static func save(_ value: String, for key: String) {
        delete(key)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.github.cfmotolink.app",
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.github.cfmotolink.app",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.github.cfmotolink.app",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
