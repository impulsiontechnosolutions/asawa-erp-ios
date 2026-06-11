//
//  Config.swift
//  AsawaERP
//
//  Mirrors the Android app's Config.kt one-for-one so the iOS build hits
//  the same endpoints with the same auth header and the same JSON shape.
//

import Foundation

enum Config {

    // ────────────── Site root ──────────────
    static let startURL = URL(string: "https://erp.asawainsulation.com")!
    static let siteHost = "erp.asawainsulation.com"

    // ────────────── ERPNext server-script endpoints ──────────────
    // Same as Android's Config.kt.
    static let logLocationURL = URL(string:
        "https://erp.asawainsulation.com/api/method/asawa_log_location")!

    static let appVersionURL = URL(string:
        "https://erp.asawainsulation.com/api/method/asawa_get_app_version")!

    // ────────────── Auth ──────────────
    // EXACT format: "token <API_KEY>:<API_SECRET>"
    // ⚠️ These credentials are visible in the binary — same trade-off as Android.
    //    Keep them in lock-step with Android's Config.kt.
    static let authHeaderValue = "token 97d54ccecdfba1e:f52a0c047ccb5a1"
    static let authHeaderName  = "Authorization"

    // ────────────── User-Agent suffix ──────────────
    // Appended so server logs can distinguish iOS app traffic from Android & web.
    static let userAgentSuffix = "AsawaERP-iOS/1.0"

    // ────────────── Asawa Connect (Raven) — placeholder until iOS build exists ──────────────
    // Once you ship the iOS Raven app, set these to its bundle id / scheme.
    static let ravenURLScheme = "asawa-connect"
    static let ravenAppStoreURL = URL(string: "https://apps.apple.com/")  // update to real listing later

    // ────────────── Deep-link scheme ──────────────
    static let appURLScheme = "asawa-mobile"

    // ────────────── Location reporter ──────────────
    // iOS has no "every 15 minutes" guarantee. Significant Location Changes
    // fires roughly every 5 minutes / 500m of movement, plus on app lifecycle
    // events. We additionally rate-limit ourselves to "no more than once per
    // 10 minutes" to avoid pestering the server when the user is wandering.
    static let minSecondsBetweenLocationPosts: TimeInterval = 10 * 60
}
