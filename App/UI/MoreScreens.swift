// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

struct ModesScreen: View {
    @ObservedObject private var store = DashStore.shared
    @State private var thumbs: [DashMode: CGImage] = [:]

    var body: some View {
        DarkPage(title: "Modos") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(DashMode.allCases) { mode in
                    Button {
                        store.setMode(mode)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            TFTImage(image: thumbs[mode])
                            Text(mode.title).font(.subheadline.weight(.semibold))
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
            Text("Las miniaturas usan datos de demostración.").font(.caption).foregroundColor(Brand.dim)

            Card {
                Text("Cambios automáticos").font(.headline)
                Toggle("Al iniciar una ruta, pasar a GPS + Música si el modo no muestra el GPS", isOn: $store.config.rules.navStartsGpsMusic)
                Toggle("Al terminar la ruta, volver al modo anterior", isOn: $store.config.rules.navEndRestores)
                Toggle("Si empieza la música sin ruta activa, pasar a Solo música", isOn: $store.config.rules.musicOnlyWithoutRoute)
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

    private func makeThumbs() {
        let now = Date()
        for mode in DashMode.allCases {
            let layout = mode == .custom ? store.config.custom.normalized : DashLayout.preset(mode)
            thumbs[mode] = DashPreview.image(DashDemo.snapshot(layout: layout, theme: store.config.theme, now: now), width: 400, height: 200, now: now)
        }
    }
}

struct MusicScreen: View {
    @ObservedObject private var store = DashStore.shared
    @ObservedObject private var music = MusicService.shared

    var body: some View {
        DarkPage(title: "Música") {
            Card {
                Text("Apple Music (app Música)").font(.headline)
                if !MusicService.supported {
                    Text("No disponible en el simulador.").font(.footnote).foregroundColor(Brand.dim)
                } else if music.authorized {
                    Label("Conectado", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.subheadline)
                } else if music.denied {
                    Text("El acceso está denegado. Actívalo en Ajustes > CFMoto Link > Contenido multimedia y Apple Music.")
                        .font(.footnote).foregroundColor(Brand.dim)
                } else {
                    Button("Permitir acceso a la música") { music.requestAccess() }
                        .buttonStyle(.borderedProminent).tint(Brand.blue)
                }
            }

            Card {
                Text("Reproducción").font(.headline)
                if music.title.isEmpty {
                    Text("No hay nada sonando en la app Música.").font(.footnote).foregroundColor(Brand.dim)
                } else {
                    HStack(spacing: 12) {
                        if let art = music.artwork {
                            Image(uiImage: art).resizable().frame(width: 64, height: 64).cornerRadius(10)
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Brand.bg).frame(width: 64, height: 64)
                                .overlay(Image(systemName: "music.note").foregroundColor(Brand.dim))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(music.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(music.artist).font(.footnote).foregroundColor(Brand.dim).lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 28) {
                    Spacer()
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }
                    Button { music.toggle() } label: { Image(systemName: music.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 44)) }
                    Button { music.next() } label: { Image(systemName: "forward.fill") }
                    Spacer()
                }
                .font(.title2)
                .tint(Brand.blue)
                .disabled(!music.authorized || !MusicService.supported)
            }

            Card {
                Text("En la pantalla de la moto").font(.headline)
                Toggle("Mostrar la portada", isOn: $store.config.showArtwork)
                Toggle("Mostrar la barra de progreso", isOn: $store.config.showProgress)
            }
            .font(.subheadline)
            .tint(Brand.blue)

            Card {
                Text("Otros servicios").font(.headline)
                Text("Spotify: no incluido en esta versión. Su SDK oficial exige registrar la app con una cuenta Premium y un identificador propio; sin ese registro no se puede activar.")
                Text("YouTube Music y otras apps: iOS no permite que una app lea lo que suena en otra, y no ofrecen un SDK para ello.")
            }
            .font(.footnote)
            .foregroundColor(Brand.dim)
        }
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
                Text("iOS no deja que una app lea las notificaciones de otras apps, así que CFMoto Link no puede mostrar mensajes de WhatsApp, Telegram ni llamadas. No hay forma permitida de hacerlo desde una app.")
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
    @AppStorage("franjaMoto") private var reserve = true
    @State private var confirming = false

    var body: some View {
        DarkPage(title: "Ajustes") {
            Card {
                Text("Pantalla de la moto").font(.headline)
                Toggle("Dejar libre la franja de abajo (velocidad, marcha y testigos)", isOn: $reserve)
                    .onChange(of: reserve) { on in HUDRenderer.reservedBottom = on ? 0.22 : 0 }
                Text("Recomendado. El cambio se aplica al volver a conectar con la moto.")
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
                Text("CFMoto Link \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") — Smart Dashboard")
                Text("Proyecto no oficial, sin relación con CFMOTO. Código: github.com/BertilM11/cfmoto-ios")
            }
            .font(.footnote)
        }
    }
}
