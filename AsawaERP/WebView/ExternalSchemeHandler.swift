//
//  ExternalSchemeHandler.swift
//  AsawaERP
//
//  Mirrors the Android shouldOverrideUrlLoading() branch that routes
//  tel:, mailto:, sms:, whatsapp:, etc. out to system apps.
//

import UIKit

enum ExternalSchemeHandler {

    /// All schemes that should never load inside the WebView.
    /// These match what Android's MainActivity.kt forwards to ACTION_VIEW.
    static let systemSchemes: Set<String> = [
        "tel", "telprompt",
        "mailto",
        "sms",
        "whatsapp",
        "geo",                 // Android-style map links — iOS resolves to Apple Maps via maps://
        "intent",              // Android-specific; we just hand to the OS, harmless
        "facetime", "facetime-audio",
        "itms-apps"
    ]

    static func openExternally(_ url: URL) {
        // Translate Android-style geo: URIs into maps:// for iOS.
        let translated: URL
        if url.scheme?.lowercased() == "geo" {
            let q = url.absoluteString
                .replacingOccurrences(of: "geo:", with: "maps://?q=")
            translated = URL(string: q) ?? url
        } else {
            translated = url
        }

        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(translated) {
                UIApplication.shared.open(translated, options: [:],
                                          completionHandler: nil)
            }
        }
    }
}
