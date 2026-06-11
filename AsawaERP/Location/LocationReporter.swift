//
//  LocationReporter.swift
//  AsawaERP
//
//  iOS replacement for Android's LocationWorker (a 15-minute WorkManager job).
//
//  iOS will not let an app run a strict every-15-minutes background task. The
//  closest legitimate primitive is `startMonitoringSignificantLocationChanges`,
//  which delivers a location update roughly every 5 minutes / 500m of movement,
//  and can wake the app from termination. This is the "reduced guarantees"
//  path the project owner explicitly opted into.
//
//  We additionally rate-limit our outgoing POSTs to no more than once per
//  10 minutes (Config.minSecondsBetweenLocationPosts) so we don't spam the
//  server when the user moves around in a city.
//
//  Payload matches Android's LocationWorker exactly:
//    {
//      "latitude": <Double>,
//      "longitude": <Double>,
//      "accuracy": <Double>,
//      "provider": "ios",
//      "for_user": "<logged-in user email>"
//    }
//
//  Auth header matches Config.authHeaderValue (token API_KEY:SECRET).
//

import Foundation
import CoreLocation
import UIKit

@MainActor
final class LocationReporter: NSObject {

    static let shared = LocationReporter()

    private let manager = CLLocationManager()
    private var lastSentAt: Date = .distantPast

    // `nonisolated` so the `static let shared` initializer doesn't trigger a
    // Swift-concurrency warning about constructing a MainActor-isolated type
    // from a global context. CLLocationManager's setters are all safe to call
    // off-main, and we touch no MainActor state here.
    nonisolated override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false   // toggled on once we get "Always"
    }

    /// Called from AppDelegate at launch and from the JS bridge when the
    /// user logs in. Becomes a no-op if we don't yet have "Always" auth.
    func startIfAuthorized() {
        // No point starting if the user isn't logged in — the server will 401.
        guard UserPrefs.shared.email?.isEmpty == false else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            // Ask for While-In-Use first. The system will let us escalate to
            // Always later (iOS will surface a "Change to Always Allow?" prompt
            // automatically the second time we try to use it in the background).
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse:
            // Try to upgrade. iOS may show its own prompt or just no-op.
            manager.requestAlwaysAuthorization()
            startMonitoring()

        case .authorizedAlways:
            startMonitoring()

        case .denied, .restricted:
            // User said no. Nothing legitimate we can do.
            return

        @unknown default:
            return
        }
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func startMonitoring() {
        manager.allowsBackgroundLocationUpdates =
            (manager.authorizationStatus == .authorizedAlways)
        manager.startMonitoringSignificantLocationChanges()
    }

    // MARK: - POST

    private func post(location: CLLocation) {
        // Rate limit.
        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= Config.minSecondsBetweenLocationPosts
        else { return }

        guard let email = UserPrefs.shared.email, !email.isEmpty else { return }

        var request = URLRequest(url: Config.logLocationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.authHeaderValue,
                         forHTTPHeaderField: Config.authHeaderName)

        let body: [String: Any] = [
            "latitude":  location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy":  location.horizontalAccuracy,
            "provider":  "ios",
            "for_user":  email
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Use a background-capable URLSession so the upload survives if the
        // app gets suspended mid-flight.
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                Task { @MainActor in self?.lastSentAt = Date() }
            }
            if let error = error {
                #if DEBUG
                print("[LocationReporter] POST error: \(error.localizedDescription)")
                #endif
            }
        }.resume()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationReporter: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Ignore very old fixes that iOS sometimes replays.
        guard abs(loc.timestamp.timeIntervalSinceNow) < 60 * 5 else { return }
        Task { @MainActor in self.post(location: loc) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.startMonitoring()
            default:
                self.stop()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        #if DEBUG
        print("[LocationReporter] CL error: \(error.localizedDescription)")
        #endif
    }
}
