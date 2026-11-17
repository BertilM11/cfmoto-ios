// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit
import MediaPlayer

/// Música del iPhone. iOS solo deja leer y controlar desde otra app lo que suena en la app
/// Música (Apple Music). Spotify va aparte, con su SDK oficial (SpotifyService).
final class MusicService: ObservableObject {
    static let shared = MusicService()

    @Published private(set) var authorized = MPMediaLibrary.authorizationStatus() == .authorized
    @Published private(set) var denied: Bool = {
        let s = MPMediaLibrary.authorizationStatus()
        return s == .denied || s == .restricted
    }()
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var playing = false
    @Published private(set) var artwork: UIImage?

    private var timer: Timer?
    private var running = false
    private var lastItemId: UInt64 = 0

    #if targetEnvironment(simulator)
    static let supported = false
    #else
    static let supported = true
    #endif

    private var player: MPMusicPlayerController { MPMusicPlayerController.systemMusicPlayer }

    func start() {
        if authorized { begin() }
    }

    func requestAccess() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorized = status == .authorized
                self.denied = status == .denied || status == .restricted
                if self.authorized { self.begin() }
            }
        }
    }

    private func begin() {
        guard MusicService.supported, !running else { return }
        running = true
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
        logLine("[MÚSICA] leyendo la app Música del iPhone")
    }

    private func refresh() {
        guard running else { return }
        let item = player.nowPlayingItem
        let isPlaying = player.playbackState == .playing
        var m = MusicSnapshot()
        if let item = item {
            m.available = true
            m.source = "Apple Music"
            m.title = item.title ?? ""
            m.artist = item.artist ?? ""
            m.duration = item.playbackDuration
            let position = player.currentPlaybackTime
            m.position = position.isFinite ? position : 0
            m.positionTime = Date().timeIntervalSinceReferenceDate
            m.playing = isPlaying
            if item.persistentID != lastItemId || artwork == nil {
                lastItemId = item.persistentID
                artwork = item.artwork?.image(at: CGSize(width: 256, height: 256))
            }
            m.artwork = artwork?.cgImage
        } else {
            artwork = nil
        }
        let active = DashStore.shared.config.musicProvider == .appleMusic
        if active { DashState.shared.setMusic(m) }
        if title != m.title { title = m.title }
        if artist != m.artist { artist = m.artist }
        if playing != isPlaying {
            playing = isPlaying
            if isPlaying && active { DashStore.shared.musicStarted() }
        }
    }

    func toggle() {
        guard running else { return }
        if playing { player.pause() } else { player.play() }
    }

    func next() {
        guard running else { return }
        player.skipToNextItem()
    }

    func previous() {
        guard running else { return }
        player.skipToPreviousItem()
    }
}
