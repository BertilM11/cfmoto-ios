// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreLocation
import Combine
import UIKit

/// Ubicación GPS de la app. Con la navegación (o el enlace con la moto) activos, pide la
/// máxima precisión y sigue recibiendo fijos con la app en segundo plano o el iPhone bloqueado.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var last: CLLocation?

    private let manager = CLLocationManager()
    private var driving = false
    /// Fijos recibidos desde que arrancó la app (para el diagnóstico).
    private(set) var fixes = 0
    /// Fijos recibidos con la app en segundo plano.
    private(set) var backgroundFixes = 0
    private var started = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        status = manager.authorizationStatus
    }

    var authorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var denied: Bool {
        status == .denied || status == .restricted
    }

    /// Pide permiso si hace falta y empieza a recibir la ubicación.
    func activate() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorized {
            startIfNeeded()
        }
    }

    /// Navegando o enviando a la moto: precisión de navegación y permiso para seguir en
    /// segundo plano (requiere el modo "location" en Info.plist).
    func setDriving(_ on: Bool) {
        driving = on
        manager.desiredAccuracy = on ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        guard authorized else { return }
        manager.allowsBackgroundLocationUpdates = on
        manager.showsBackgroundLocationIndicator = on
    }

    private func startIfNeeded() {
        if !started {
            started = true
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if authorized {
            startIfNeeded()
            setDriving(driving)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        // Descartar fijos viejos que iOS entrega de su caché al arrancar.
        if abs(location.timestamp.timeIntervalSinceNow) > 15 { return }
        fixes += 1
        if UIApplication.shared.applicationState == .background { backgroundFixes += 1 }
        last = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logLine("[GPS] error: \(error.localizedDescription)")
    }
}
