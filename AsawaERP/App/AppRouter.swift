//
//  AppRouter.swift
//  AsawaERP
//
//  Tiny app-wide router. Owns "what should be on screen" plus the URL the
//  WebView should currently be pointing at. Lives in an ObservableObject so
//  any SwiftUI view can react.
//

import Foundation
import UIKit

@MainActor
final class AppRouter: ObservableObject {

    enum Destination: Equatable {
        case landing
        case webView(URL)
    }

    /// Where we are right now. Starts on the landing page.
    @Published var destination: Destination = .landing

    /// Helper for the landing page button.
    func openERP() {
        destination = .webView(Config.startURL)
    }

    /// Helper for the landing page Raven button.
    func openRaven() {
        // First, try to launch the Asawa Connect (Raven) iOS app via its
        // custom scheme. If it isn't installed, fall back to the App Store.
        let scheme = URL(string: "\(Config.ravenURLScheme)://")!
        if UIApplication.shared.canOpenURL(scheme) {
            UIApplication.shared.open(scheme)
            return
        }
        // Not installed → take the user to the App Store listing (placeholder for now).
        if let store = Config.ravenAppStoreURL {
            UIApplication.shared.open(store)
        }
    }

    /// Called from `.onOpenURL` for both the asawa-mobile:// scheme and
    /// (when entitled) universal links to https://erp.asawainsulation.com/app/*.
    func handleIncoming(url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""

        // asawa-mobile://app/something  →  https://erp.asawainsulation.com/app/something
        if scheme == Config.appURLScheme {
            // Strip the scheme and rebuild against the ERP origin.
            // Path & query are passed through.
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = Config.siteHost
            comps.path = url.path.isEmpty ? "/" : url.path
            comps.percentEncodedQuery = url.percentEncodedQuery
            comps.fragment = url.fragment
            destination = .webView(comps.url ?? Config.startURL)
            return
        }

        // Universal link path: already a full https URL to the same host.
        if scheme == "https", url.host == Config.siteHost {
            destination = .webView(url)
            return
        }

        // Unknown — just open ERP root.
        destination = .webView(Config.startURL)
    }
}
