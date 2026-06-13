//
//  DiagnosticView.swift
//  AsawaERP
//
//  Hidden diagnostic screen. Accessible by tapping the version footer on
//  the Landing screen 7 times in a row. Shows live state of:
//    • App identity (version, build, bundle id, device)
//    • Network reachability
//    • Logged-in user (captured from JS bridge)
//    • Location authorization + monitoring status
//    • Last GPS fix + last POST to asawa_log_location
//    • Last-known WebView URL
//
//  And exposes manual actions:
//    • Force a location POST now (skip the 10-min rate limiter)
//    • Request "Always" location upgrade
//    • Open iOS Settings for this app
//    • Clear cookies & reload WebView
//
//  This screen is your single best friend on day-one of TestFlight install.
//  If something seems broken, come here first — it'll show you what's
//  actually happening before you have to dig through server logs.
//

import SwiftUI
import UIKit
import CoreLocation
import WebKit

struct DiagnosticView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var reachability = Reachability.shared
    @StateObject private var locator = LocationReporter.shared
    @State private var lastWebViewURL: String = "—"
    @State private var copyHint: String? = nil

    var body: some View {
        NavigationView {
            List {
                Section("App") {
                    row("Version", appVersion)
                    row("Build", appBuild)
                    row("Bundle ID", Bundle.main.bundleIdentifier ?? "—")
                    row("Device", UIDevice.current.model + " · iOS " + UIDevice.current.systemVersion)
                }

                Section("Network") {
                    row("Reachability", reachability.isOnline ? "✅ online" : "❌ offline")
                    row("ERP host", Config.siteHost)
                }

                Section("Session") {
                    row("Logged-in user", UserPrefs.shared.email ?? "—")
                    row("Last login ping", UserPrefs.shared.loginPingDone ? "yes" : "no")
                }

                Section("Location") {
                    row("Authorization", authStatusLabel(locator.authorizationStatus))
                    row("Monitoring", locator.isMonitoring ? "✅ active" : "⏸ paused")
                    row("Last GPS fix", lastFixLabel)
                    row("Last POST", lastPostLabel)
                    row("POST attempts", "\(locator.attemptCount) (✅ \(locator.successCount))")
                }

                Section("Actions") {
                    Button {
                        locator.forcePostNow()
                    } label: {
                        Label("Force location POST now", systemImage: "location.fill")
                    }

                    Button {
                        locator.requestAlwaysUpgrade()
                    } label: {
                        Label("Request 'Always' location", systemImage: "location.circle")
                    }

                    Button {
                        openSettings()
                    } label: {
                        Label("Open iOS Settings for this app", systemImage: "gear")
                    }

                    Button(role: .destructive) {
                        clearWebViewData()
                    } label: {
                        Label("Clear cookies & cache", systemImage: "trash")
                    }
                }

                Section("Tips") {
                    Text("If 'POST attempts' stays at 0 even after moving 500m+, location permission is probably stuck on 'When In Use'. Open iOS Settings and switch to 'Always'.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Tap 'Force location POST now' to verify the round-trip immediately — it bypasses the 10-minute rate limit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        copyAllToPasteboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let hint = copyHint {
                    Text(hint)
                        .font(.footnote)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Subviews

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .font(.footnote.monospaced())
        }
    }

    // MARK: - Computed labels

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    private var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    private var lastFixLabel: String {
        guard let f = locator.lastFix else { return "—" }
        let fmt = DateFormatter()
        fmt.dateStyle = .none; fmt.timeStyle = .medium
        return String(format: "%.5f, %.5f  (±%.0fm)  @ %@",
                      f.latitude, f.longitude, f.accuracy,
                      fmt.string(from: f.timestamp))
    }

    private var lastPostLabel: String {
        guard let r = locator.lastPostResult else { return "—" }
        let fmt = DateFormatter()
        fmt.dateStyle = .none; fmt.timeStyle = .medium
        let when = fmt.string(from: r.timestamp)
        if r.isSuccess {
            return "✅ \(r.statusCode ?? 0) @ \(when)"
        }
        let codeStr = r.statusCode.map { "HTTP \($0)" } ?? "no response"
        let errStr = r.errorMessage.map { " — \($0)" } ?? ""
        return "❌ \(codeStr)\(errStr) @ \(when)"
    }

    private func authStatusLabel(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "not determined"
        case .restricted:    return "restricted"
        case .denied:        return "❌ denied"
        case .authorizedAlways:    return "✅ Always"
        case .authorizedWhenInUse: return "⚠️ While Using only"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Actions

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func clearWebViewData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        ) {
            UserPrefs.shared.email = nil
            UserPrefs.shared.loginPingDone = false
            showHint("Cookies & cache cleared")
        }
    }

    private func copyAllToPasteboard() {
        var lines: [String] = []
        lines.append("Asawa ERP Diagnostics")
        lines.append("Version: \(appVersion) (\(appBuild))")
        lines.append("Bundle: \(Bundle.main.bundleIdentifier ?? "—")")
        lines.append("Device: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)")
        lines.append("Online: \(reachability.isOnline)")
        lines.append("User: \(UserPrefs.shared.email ?? "—")")
        lines.append("Loc auth: \(authStatusLabel(locator.authorizationStatus))")
        lines.append("Monitoring: \(locator.isMonitoring)")
        lines.append("Last fix: \(lastFixLabel)")
        lines.append("Last POST: \(lastPostLabel)")
        lines.append("Attempts: \(locator.attemptCount) / Successes: \(locator.successCount)")
        UIPasteboard.general.string = lines.joined(separator: "\n")
        showHint("Copied to clipboard — paste anywhere")
    }

    private func showHint(_ s: String) {
        copyHint = s
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation { copyHint = nil }
            }
        }
    }
}

#Preview {
    DiagnosticView()
}
