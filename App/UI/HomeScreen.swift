// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct HomeScreen: View {
    @Binding var tab: Int
    @ObservedObject private var store = DashStore.shared
    @ObservedObject private var link = LinkModel.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var spotify = SpotifyService.shared

    private var nowTitle: String { store.config.musicProvider == .spotify ? spotify.title : music.title }
    private var nowArtist: String { store.config.musicProvider == .spotify ? spotify.artist : music.artist }
    private var nowPlaying: Bool { store.config.musicProvider == .spotify ? spotify.playing : music.playing }

    var body: some View {
        NavigationStack {
            DarkPage(title: "CFMoto Link") {
                Card {
                    HStack(spacing: 10) {
                        Circle().fill(link.linked ? Color.green : Color.gray).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.linked ? "Enviando a la moto" : "Moto sin conectar").font(.headline)
                            Text(link.broadcasting && !link.running ? "Duplicando la pantalla del iPhone" : link.status)
                                .font(.footnote).foregroundColor(Brand.dim)
                        }
                        Spacer()
                    }
                    Button {
                        if link.running { link.disconnect() } else { link.connect() }
                    } label: {
                        Label(link.running ? "Detener" : "Conectar y enviar el panel", systemImage: link.running ? "stop.fill" : "antenna.radiowaves.left.and.right")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(link.running ? .red : Brand.blue)
                    .disabled(link.broadcasting && !link.running)
                    Text("Antes de conectar: abre el código QR en la moto y une el iPhone a su Wi-Fi (DIRECT-…-CFMOTO).")
                        .font(.caption).foregroundColor(Brand.dim)
                }

                Card {
                    HStack {
                        Text("Lo que recibe la moto").font(.headline)
                        Spacer()
                        Text(store.config.mode.label).font(.subheadline.weight(.semibold)).foregroundColor(Brand.blue).lineLimit(1)
                    }
                    TFTPreview(demo: false)
                    ModeChips()
                }

                Button {
                    tab = 1
                } label: {
                    Label("Ir a navegación", systemImage: "location.north.line.fill")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(Brand.blue)

                if !nowTitle.isEmpty {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: nowPlaying ? "play.fill" : "pause.fill").foregroundColor(Brand.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nowTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(nowArtist).font(.footnote).foregroundColor(Brand.dim).lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
