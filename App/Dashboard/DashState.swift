// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Estado del panel listo para dibujar. La app lo escribe desde el hilo principal y el dibujo
/// para la moto lo lee desde el suyo.
final class DashState {
    static let shared = DashState()

    private let lock = NSLock()
    private var base = DashSnapshot()
    private var noticeSeconds: Double = 8

    func apply(_ c: DashConfig) {
        lock.lock()
        base.layout = c.layout
        base.theme = c.theme
        base.privacy = c.noticePrivacy
        base.showArtwork = c.showArtwork
        base.showProgress = c.showProgress
        noticeSeconds = c.noticeSeconds
        lock.unlock()
    }

    func setMusic(_ m: MusicSnapshot) {
        lock.lock()
        base.music = m
        lock.unlock()
    }

    func post(_ n: NoticeSnapshot) {
        lock.lock()
        base.notices.append(n)
        if base.notices.count > 12 { base.notices.removeFirst(base.notices.count - 12) }
        lock.unlock()
    }

    /// Estado actual con la navegación al día y solo los avisos que aún no caducan.
    func snapshot(now: Date = Date()) -> DashSnapshot {
        let nav = HUDState.shared.get()
        lock.lock()
        var s = base
        let t = now.timeIntervalSinceReferenceDate
        let keep = noticeSeconds
        base.notices.removeAll { t - $0.time > 600 }
        lock.unlock()
        s.nav = nav
        s.notices = s.notices.filter { t - $0.time <= keep }
        return s
    }
}
