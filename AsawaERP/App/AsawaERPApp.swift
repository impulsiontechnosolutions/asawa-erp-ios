//
//  AsawaERPApp.swift
//  AsawaERP
//
//  The SwiftUI @main entry. We use the modern SwiftUI App lifecycle and
//  bridge to UIKit only for the WKWebView (which still has the smoothest
//  ergonomics in UIKit).
//

import SwiftUI

@main
struct AsawaERPApp: App {

    // Plug in our UIKit AppDelegate for the few hooks SwiftUI doesn't expose.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Track deep links so SwiftUI navigation can react.
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                // asawa-mobile://… and (later) https://erp.asawainsulation.com/app/…
                .onOpenURL { url in
                    router.handleIncoming(url: url)
                }
        }
    }
}
