//
//  LocationReporter.swift
//  AsawaERP
//
//  iOS replacement for Android's LocationWorker.
//
//  Uses significant location changes (the only legitimate primitive that
//  fires while the app is suspended or terminated). Rate-limited so we
//  never POST more often than once per Config.minSecondsBetweenLocationPosts.
//
//  Publishes its state for the DiagnosticView so you can verify it's
//  actually doing something on a real iPhone without needing to log into
//  the server to check Mobile Location Log entries.
//

import Foundation
import CoreLocation
import UIKit

@MainActor
final class LocationReporter: NSObject, ObservableObject {

    static let shared = LocationReporter()

    // ────────────────────── Observable state (for DiagnosticView) ──────────────────────
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastFix: Fix? = nil
    @Published private(set) var lastPostResult: PostResult? = nil
    @Published private(set) var attemptCount: Int = 0
    @Published private(set) var successCount: Int = 0

    struct Fix: Equatable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let timestamp: Date
    }
    struct PostResult: Equatable {
        let timestamp: Date
        let statusCode: Int?     // nil if request never completed
        let errorMessage: String? // nil on success
        var isSuccess: Bool { (statusCode.map { (200...299).contains($0) }) ?? false }
    }

    private let manager = CLLocationManager()
    private var lastSentAt: Date = .distantPast

    nonisolated override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
        Task { @MainActor in
            self.authorizationStatus = self.manager.authorizationStatus
        }
    }

    // ────────────────────── Public API ──────────────────────

    /// Called from AppDelegate at launch and from the JS bridge after login.
    func startIfAuthorized() {
        guard UserPrefs.shared.email?.isEmpty == false else {
            #if DEBUG
            print("[LocationReporter] no logged-in user yet — deferring start")
            #endif
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startMonitoring()
        case .authorizedAlways:
            startMonitoring()
        case .denied, .restricted:
            return
        @unknown default:
            return
        }
    }

    /// Stop everything (called by JS-bridge logout).
    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        isMonitoring = false
    }

    /// Request "Always" upgrade explicitly. Surfaced as a button in DiagnosticView.
    func requestAlwaysUpgrade() {
        manager.requestAlwaysAuthorization()
    }

    /// Force an immediate one-shot location fetch + POST, bypassing the rate limiter.
    /// Surfaced as a button in DiagnosticView so you can verify the round-trip on
    /// first install without waiting 10 minutes for significant changes to fire.
    func forcePostNow() {
        #if DEBUG
        print("[LocationReporter] forcePostNow tapped")
        #endif
        // Reset the rate limiter so the upcoming POST is not throttled.
        lastSentAt = .distantPast
        manager.requestLocation()
    }

    // ────────────────────── Internals ──────────────────────

    private func startMonitoring() {
        manager.allowsBackgroundLocationUpdates =
            (manager.authorizationStatus == .authorizedAlways)
        manager.startMonitoringSignificantLocationChanges()
        isMonitoring = true
        #if DEBUG
        print("[LocationReporter] monitoring started (always=\(manager.authorizationStatus == .authorizedAlways))")
        #endif
    }

    private func post(location: CLLocation) {
        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= Config.minSecondsBetweenLocationPosts
        else {
            #if DEBUG
            print("[LocationReporter] rate-limited; \(Int(now.timeIntervalSince(lastSentAt)))s since last")
            #endif
            return
        }

        guard let email = UserPrefs.shared.email, !email.isEmpty else {
            #if DEBUG
            print("[LocationReporter] no email — cannot POST")
            #endif
            return
        }

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

        attemptCount += 1

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self else { return }
                let code = (response as? HTTPURLResponse)?.statusCode
                let errMsg = error?.localizedDescription
                self.lastPostResult = PostResult(
                    timestamp: Date(),
                    statusCode: code,
                    errorMessage: errMsg
                )
                if let c = code, (200...299).contains(c) {
                    self.lastSentAt = Date()
                    self.successCount += 1
                    #if DEBUG
                    print("[LocationReporter] POST OK (\(c))")
                    #endif
                } else {
                    #if DEBUG
                    print("[LocationReporter] POST failed code=\(code.map(String.init) ?? "nil") err=\(errMsg ?? "nil")")
                    #endif
                }
            }
        }.resume()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationReporter: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Ignore obviously stale fixes that iOS sometimes replays.
        guard abs(loc.timestamp.timeIntervalSinceNow) < 60 * 5 else { return }
        Task { @MainActor in
            self.lastFix = Fix(
                latitude:  loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                accuracy:  loc.horizontalAccuracy,
                timestamp: loc.timestamp
            )
            self.post(location: loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
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
        Task { @MainActor in
            self.lastPostResult = PostResult(
                timestamp: Date(),
                statusCode: nil,
                errorMessage: "CL error: \(error.localizedDescription)"
            )
        }
        #if DEBUG
        print("[LocationReporter] CL error: \(error.localizedDescription)")
        #endif
    }
}
