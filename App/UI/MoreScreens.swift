// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

struct ModesScreen: View {
    @ObservedObject private var store = DashStore.shared
    @State private var thumbs: [DashMode: CGImage] = [:]

    var body: some View {
        DarkPage(title: "Modos") {
            Text("Modos principales").font(.headline)
            grid(DashMode.primary)
            Text("Otros modos").font(.headline)
            grid(DashMode.others)
            Text("Las miniaturas usan datos de demostración y el mapa simplificado. El modo 5 es el que editas en Mi pantalla.")
                .font(.caption).foregroundColor(Brand.dim)

            Card {
                Text("Cambios automáticos").font(.headline)
                Toggle("Al iniciar una ruta, pasar a Navegación + Música si el modo no muestra el mapa", isOn: $store.config.rules.navStartsGpsMusic)
                Toggle("Al terminar la ruta, volver al modo anterior", isOn: $store.config.rules.navEndRestores)
                Toggle("Si empieza la música sin ruta activa, pasar a Música", isOn: $store.config.rules.musicOnlyWithoutRoute)
                Toggle("Cerca de un giro, dar prioridad a las indicaciones", isOn: $store.config.rules.turnPriority)
                Text("Si se pierde la conexión, la app lo avisa y al reconectar la moto recibe el mismo modo: el modo activo no depende del enlace.")
                    .font(.caption).foregroundColor(Brand.dim)
            }
            .font(.subheadline)
            .tint(Brand.blue)
        }
        .onAppear { makeThumbs() }
        .onChange(of: store.config.custom) { _ in makeThumbs() }
        .onChange(of: store.config.theme) { _ in makeThumbs() }
    }

    private func grid(_ modes: [DashMode]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(modes) { mode in
                Button {
                    store.setMode(mode)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        TFTImage(image: thumbs[mode], showBikeBand: false)
                        Text(mode.label).font(.subheadline.weight(.semibold)).lineLimit(2)
                    }
                    .padding(8)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(store.config.mode == mode ? Brand.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func makeThumbs() {
        let now = Date()
        for mode in DashMode.allCases {
            let layout = mode == .custom ? store.config.custom.normalized : DashLayout.preset(mode)
            var demo = DashDemo.snapshot(layout: layout, theme: store.config.theme, now: now)
            demo.mapSettings = store.config.map
            thumbs[mode] = DashPreview.image(demo, width: 400, height: 200, now: now)
        }
    }
}

struct MusicScreen: View {
    @ObservedObject private var store = DashStore.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var spotify = SpotifyService.shared
    @ObservedObject private var spotifyWeb = SpotifyWeb.shared

    private var useSpotify: Bool { store.config.musicProvider == .spotify }

    var body: some View {
        DarkPage(title: "Música") {
            Card {
                Text("Qué música muestra la moto").font(.headline)
                Picker("Proveedor", selection: $store.config.musicProvider) {
                    ForEach(MusicProvider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("La música no interfiere con el GPS ni con la conexión con la moto: solo se lee la canción y se dibuja en el panel.")
                    .font(.caption).foregroundColor(Brand.dim)
            }
            .tint(Brand.blue)

            if useSpotify { spotifyCard } else { appleCard }

            Card {
                Text("Reproducción").font(.headline)
                let title = useSpotify ? spotify.title : music.title
                let artist = useSpotify ? spotify.artist : music.artist
                if title.isEmpty {
                    Text(useSpotify ? "No hay nada sonando en Spotify (o no está conectado)." : "No hay nada sonando en la app Música.")
                        .font(.footnote).foregroundColor(Brand.dim)
                } else {
                    HStack(spacing: 12) {
                        if !useSpotify, let art = music.artwork {
                            Image(uiImage: art).resizable().frame(width: 64, height: 64).cornerRadius(10)
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Brand.bg).frame(width: 64, height: 64)
                                .overlay(Image(systemName: "music.note").foregroundColor(Brand.dim))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(artist).font(.footnote).foregroundColor(Brand.dim).lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 28) {
                    Spacer()
                    Button { useSpotify ? spotify.previous() : music.previous() } label: { Image(systemName: "backward.fill") }
                    Button { useSpotify ? spotify.toggle() : music.toggle() } label: {
                        Image(systemName: (useSpotify ? spotify.playing : music.playing) ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 44))
                    }
                    Button { useSpotify ? spotify.next() : music.next() } label: { Image(systemName: "forward.fill") }
                    Spacer()
                }
                .font(.title2)
                .tint(Brand.blue)
                .disabled(useSpotify ? !spotify.connected : (!music.authorized || !MusicService.supported))
                Text("En la moto se ven los mismos botones, pero no se pueden pulsar (su pantalla no es táctil y el protocolo no envía teclas): para cambiar de canción, usa estos del iPhone.")
                    .font(.caption).foregroundColor(Brand.dim)
            }

            Card {
                Text("En la pantalla de la moto").font(.headline)
                Toggle("Mostrar la portada", isOn: $store.config.showArtwork)
                Toggle("Mostrar la barra de progreso", isOn: $store.config.showProgress)
                Text("El tamaño de la tarjeta de música se elige en Mi pantalla (compacta o grande).")
                    .font(.caption).foregroundColor(Brand.dim)
            }
            .font(.subheadline)
            .tint(Brand.blue)

            Card {
                Text("Otras apps").font(.headline)
                Text("YouTube Music y otras apps: iOS no permite que una app lea lo que suena en otra, y no ofrecen un SDK para ello.")
            }
            .font(.footnote)
            .foregroundColor(Brand.dim)
        }
    }

    private var appleCard: some View {
        Card {
            Text("Apple Music (app Música)").font(.headline)
            if !MusicService.supported {
                Text("No disponible en el simulador.").font(.footnote).foregroundColor(Brand.dim)
            } else if music.authorized {
                Label("Conectado", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.subheadline)
            } else if music.denied {
                Text("El acceso está denegado. Actívalo en Ajustes > MotoLink > Contenido multimedia y Apple Music.")
                    .font(.footnote).foregroundColor(Brand.dim)
            } else {
                Button("Permitir acceso a la música") { music.requestAccess() }
                    .buttonStyle(.borderedProminent).tint(Brand.blue)
            }
        }
    }

    private var spotifyCard: some View {
        Card {
            Text("Spotify").font(.headline)
            Text("Con el SDK oficial de Spotify. Necesitas registrar tu propia app (gratis) en developer.spotify.com; desde 2026 Spotify exige que la cuenta dueña tenga Premium.")
                .font(.footnote).foregroundColor(Brand.dim)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Crea una app en developer.spotify.com > Dashboard, con «iOS» como plataforma.")
                Text("2. Dirección de vuelta (Redirect URI): cfmotolink://spotify-login")
                Text("3. Identificador del paquete (Bundle ID): io.github.cfmotolink.app")
                Text("4. Copia su Client ID aquí y toca Conectar. Ten Spotify instalado.")
            }
            .font(.caption).foregroundColor(Brand.dim)
            TextField("Client ID de tu app de Spotify", text: $store.config.spotifyClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .padding(8)
                .background(Brand.bg, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Circle().fill(spotify.connected ? Color.green : Color.gray).frame(width: 10, height: 10)
                Text(spotify.statusText).font(.footnote)
                Spacer()
            }
            if spotify.connected {
                Button("Desconectar") { spotify.disconnect() }
                    .buttonStyle(.bordered).tint(.red)
            } else {
                Button("Conectar con Spotify") { spotify.connect(clientID: store.config.spotifyClientID) }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.12, green: 0.84, blue: 0.38))
                    .disabled(store.config.spotifyClientID.trimmingCharacters(in: .whitespaces).isEmpty || !SpotifyService.available)
            }
            Text("El permiso de Spotify dura una hora; si caduca, toca Conectar otra vez. Conecta antes de salir: con el iPhone bloqueado no siempre se puede reconectar.")
                .font(.caption).foregroundColor(Brand.dim)
            Divider()
            // 0.9.1: Spotify por internet, para cuando la conexión local se corta.
            Text("Spotify por internet (recomendado)").font(.subheadline.weight(.semibold))
            Text("Si Spotify se pausa o entra una llamada, la conexión local se corta y no se puede rehacer con el iPhone bloqueado. Con esto, MotoLink pregunta a Spotify por internet qué suena (cada 2 s mientras suena y al cambiar de canción, unos 4–7 MB por hora) y los botones siguen funcionando (Premium). Se usa solo cuando la conexión local no está.")
                .font(.caption).foregroundColor(Brand.dim)
            VStack(alignment: .leading, spacing: 4) {
                Text("Antes, en developer.spotify.com › tu app › Settings › Edit:")
                Text("• En «APIs used» marca también «Web API».")
                Text("• Agrega la dirección de vuelta: cfmotolink://spotify-web")
            }
            .font(.caption).foregroundColor(Brand.dim)
            HStack {
                Circle().fill(spotifyWeb.signedIn ? Color.green : Color.gray).frame(width: 10, height: 10)
                Text(spotifyWeb.statusText).font(.footnote)
                Spacer()
            }
            if spotifyWeb.signedIn {
                Button("Cerrar sesión por internet") { spotifyWeb.signOut() }
                    .buttonStyle(.bordered).tint(.red)
            } else {
                Button("Iniciar sesión en Spotify") { spotifyWeb.signIn(clientID: store.config.spotifyClientID) }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.12, green: 0.84, blue: 0.38))
                    .disabled(store.config.spotifyClientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("El permiso se guarda solo en el llavero de este iPhone; «Cerrar sesión» lo borra.")
                .font(.caption).foregroundColor(Brand.dim)
            // Spotify pide que cualquier uso de su contenido enlace con su app.
            Button(spotifyInstalled ? "ABRIR SPOTIFY" : "OBTENER SPOTIFY GRATIS") { openSpotify() }
                .font(.footnote.weight(.bold))
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    private var spotifyInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func openSpotify() {
        let link = spotifyInstalled ? "spotify:" : "https://apps.apple.com/app/spotify-music-and-podcasts/id324684580"
        if let url = URL(string: link) { UIApplication.shared.open(url) }
    }
}

struct NoticesScreen: View {
    @ObservedObject private var store = DashStore.shared

    var body: some View {
        DarkPage(title: "Notificaciones") {
            Card {
                Text("Fuentes permitidas").font(.headline)
                Toggle("Navegación (ruta iniciada, recálculo, llegada)", isOn: $store.config.noticeNav)
                Toggle("Conexión con la moto", isOn: $store.config.noticeLink)
                Toggle("Batería baja del iPhone", isOn: $store.config.noticeBattery)
            }
            .font(.subheadline)
            .tint(Brand.blue)

            Card {
                Text("Privacidad y duración").font(.headline)
                Toggle("Ocultar el texto en la moto", isOn: $store.config.noticePrivacy)
                Text("Tiempo en pantalla: \(Int(store.config.noticeSeconds)) s").font(.footnote).foregroundColor(Brand.dim)
                Slider(value: $store.config.noticeSeconds, in: 3...30, step: 1)
            }
            .font(.subheadline)
            .tint(Brand.blue)

            Card {
                Text("WhatsApp y otras apps").font(.headline)
                Text("iOS no deja que una app lea las notificaciones de otras apps, así que MotoLink no puede mostrar mensajes de WhatsApp, Telegram ni llamadas. No hay forma permitida de hacerlo desde una app.")
                    .font(.footnote).foregroundColor(Brand.dim)
            }

            Button {
                store.notify(.test, "Aviso de prueba", "Enviado desde el iPhone")
            } label: {
                Label("Enviar un aviso de prueba", systemImage: "bell.badge.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Brand.blue)

            Card {
                Text("Recientes").font(.headline)
                if store.history.isEmpty {
                    Text("Todavía no hay avisos.").font(.footnote).foregroundColor(Brand.dim)
                }
                ForEach(store.history.prefix(12)) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.subheadline.weight(.semibold))
                        Text(n.text).font(.footnote).foregroundColor(Brand.dim)
                    }
                }
            }
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject private var store = DashStore.shared
    @AppStorage("franjaLibre") private var reserve = false
    @State private var confirming = false

    var body: some View {
        DarkPage(title: "Ajustes") {
            Card {
                Text("Pantalla de la moto").font(.headline)
                Toggle("Dejar vacía la parte de abajo de la imagen", isOn: $reserve)
                    .onChange(of: reserve) { on in HUDRenderer.reservedBottom = on ? 0.22 : 0 }
                Text("Apagado: la app usa toda la imagen. La moto muestra velocidad, marcha y testigos en su propia franja, debajo de la imagen, y no se tapan. Se aplica al volver a conectar.")
                    .font(.caption).foregroundColor(Brand.dim)
                Text("Tema del panel").font(.footnote).foregroundColor(Brand.dim)
                Picker("Tema", selection: $store.config.theme) {
                    ForEach(DashTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .font(.subheadline)
            .tint(Brand.blue)

            Card {
                Text("Idioma y rendimiento").font(.headline)
                Text("Idioma: español (único en esta versión).")
                Text("Imagen para la moto: 800×400, hasta 10 imágenes por segundo, H.264.")
            }
            .font(.footnote)

            Button(role: .destructive) {
                confirming = true
            } label: {
                Label("Restaurar modos, perfiles y reglas", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .confirmationDialog("Se borran tus perfiles y diseños guardados.", isPresented: $confirming, titleVisibility: .visible) {
                Button("Restaurar", role: .destructive) { store.restoreDefaults() }
                Button("Cancelar", role: .cancel) {}
            }

            Card {
                Text("Acerca de").font(.headline)
                Text("MotoLink \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") — Smart Dashboard")
                Text("Una creación de BERL · Bertil Raxón")
                Text("Proyecto no oficial, sin relación con CFMOTO. Código: github.com/BertilM11/cfmoto-ios")
                Text("Créditos: datos del mapa © colaboradores de OpenStreetMap (ODbL). Tema Póster inspirado en prettymaps de Marcelo Prates (AGPL-3.0). Letras sincronizadas de LRCLIB.")
                    .foregroundStyle(.secondary)
                BrandFooter(height: 58).padding(.top, 4)
            }
            .font(.footnote)
        }
    }
}
