//
//  VersionChecker.swift
//  AsawaERP
//
//  Calls the server-script endpoint
//    GET https://erp.asawainsulation.com/api/method/asawa_get_app_version
//  exactly the same way Android does at launch (checkForForceUpdate()).
//
//  Expected response shape from the Frappe server-script:
//   {
//     "message": {
//       "latest_version":        "1.2",
//       "min_supported_version": "1.0",
//       "update_url":            "https://apps.apple.com/app/idXXXXXXXXX",  // or any URL
//       "message":               "A new version is available. Please update."
//     }
//   }
//
//  Behavior:
//    • If the user's CFBundleShortVersionString is LESS THAN min_supported_version
//      → publish a forceUpdate event (UI surfaces a blocking alert).
//    • Otherwise no-op.
//

import Foundation

@MainActor
final class VersionChecker: ObservableObject {

    static let shared = VersionChecker()

    struct ForceUpdate {
        let message: String
        let updateURL: URL?
    }

    @Published var forceUpdate: ForceUpdate? = nil

    func checkOnLaunch() {
        Task.detached(priority: .background) { [weak self] in
            await self?.performCheck()
        }
    }

    private func performCheck() async {
        var request = URLRequest(url: Config.appVersionURL)
        request.httpMethod = "GET"
        request.setValue(Config.authHeaderValue,
                         forHTTPHeaderField: Config.authHeaderName)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            // Frappe wraps server-script returns in {"message": {...}}.
            let payload = (json["message"] as? [String: Any]) ?? json

            let minSupported = (payload["min_supported_version"] as? String) ?? ""
            let updateURL = (payload["update_url"] as? String).flatMap(URL.init(string:))
            let displayMessage = (payload["message"] as? String) ??
                "A new version of Asawa ERP is required to continue."

            let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                           as? String) ?? "0"

            if Self.compareSemver(current, isLessThan: minSupported) {
                await MainActor.run {
                    self.forceUpdate = ForceUpdate(message: displayMessage,
                                                   updateURL: updateURL)
                }
            }
        } catch {
            // Network failures should never block the app — silently ignore.
        }
    }

    /// True if `a` is strictly less than `b` (semver-style, both like "1.2.3").
    static func compareSemver(_ a: String, isLessThan b: String) -> Bool {
        if b.isEmpty { return false }
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va < vb { return true }
            if va > vb { return false }
        }
        return false
    }
}
