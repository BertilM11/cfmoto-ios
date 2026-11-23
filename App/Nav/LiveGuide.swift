// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.8.2: lleva la guía a la pantalla bloqueada y a la Dynamic Island (Live Activity). Empieza
// con la navegación, se actualiza cuando cambia algo que se ve (maniobra, distancia redondeada,
// límite) y termina al llegar o al cancelar. Sin servidores: solo actualizaciones locales.
import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

final class LiveGuide {
    static let shared = LiveGuide()

    private var activity: Any?
    private var lastState: Any?
    private var lastPush = Date.distantPast
    private var cleaned = false

    func update(_ s: HUDSnapshot) {
        if Thread.isMainThread {
            handle(s)
        } else {
            DispatchQueue.main.async { self.handle(s) }
        }
    }

    private func handle(_ s: HUDSnapshot) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) { run(s) }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private func run(_ s: HUDSnapshot) {
        typealias A = NavActivityAttributes
        if !cleaned {
            cleaned = true
            // Las que hayan quedado de un cierre anterior de la app.
            for old in Activity<A>.activities {
                Task { await old.end(nil, dismissalPolicy: .immediate) }
            }
        }
        let current = activity as? Activity<A>
        let wanted = DashStore.shared.config.map.liveActivity && ActivityAuthorizationInfo().areActivitiesEnabled
        let state = A.ContentState(kind: s.kind.rawValue, distance: s.distanceToManeuver, instruction: s.instruction,
                                   remainingDistance: s.remainingDistance, eta: s.eta ?? Date().addingTimeInterval(s.remainingTime),
                                   arrived: s.arrived, rerouting: s.rerouting, speedLimit: s.speedLimit)
        guard wanted else {
            if let a = current { end(a, final: nil) }
            return
        }
        if s.navigating {
            if let a = current {
                guard shouldPush(state) else { return }
                lastState = state
                lastPush = Date()
                Task { await a.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(180))) }
            } else {
                do {
                    let name = s.destinationName.isEmpty ? "Destino" : s.destinationName
                    activity = try Activity.request(attributes: A(destination: name),
                                                    content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)),
                                                    pushType: nil)
                    lastState = state
                    lastPush = Date()
                    logLine("[GUÍA] en la pantalla bloqueada")
                } catch {
                    logLine("[GUÍA] no se pudo mostrar en la pantalla bloqueada: \(error.localizedDescription)")
                }
            }
        } else if let a = current {
            end(a, final: s.arrived ? state : nil)
        }
    }

    @available(iOS 16.2, *)
    private func end(_ a: Activity<NavActivityAttributes>, final: NavActivityAttributes.ContentState?) {
        activity = nil
        lastState = nil
        let content = final.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = final == nil ? .immediate : .after(Date().addingTimeInterval(120))
        Task { await a.end(content, dismissalPolicy: policy) }
    }

    /// Se actualiza solo si cambia lo que se ve, y como mucho cada 2 s (o cada 30 s si no cambia
    /// nada visible), para no gastar batería ni el límite de actualizaciones de iOS.
    @available(iOS 16.2, *)
    private func shouldPush(_ state: NavActivityAttributes.ContentState) -> Bool {
        let since = Date().timeIntervalSince(lastPush)
        guard let last = lastState as? NavActivityAttributes.ContentState else { return true }
        let visible = last.kind != state.kind || last.instruction != state.instruction || last.rerouting != state.rerouting
            || last.speedLimit != state.speedLimit
            || LiveFormat.distance(last.distance) != LiveFormat.distance(state.distance)
            || LiveFormat.distance(last.remainingDistance) != LiveFormat.distance(state.remainingDistance)
            || abs(last.eta.timeIntervalSince(state.eta)) >= 60
        if visible { return since >= 2 }
        return since >= 30
    }
    #endif
}
