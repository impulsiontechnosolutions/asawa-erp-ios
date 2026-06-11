//
//  RootView.swift
//  AsawaERP
//
//  Top-level switcher. Either we're on the landing chooser, or we're
//  inside the WebView. SwiftUI redraws when AppRouter publishes a change.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            switch router.destination {
            case .landing:
                LandingView()
                    .transition(.opacity)

            case .webView(let url):
                WebViewContainer(initialURL: url)
                    .ignoresSafeArea(.keyboard)   // keyboard shouldn't shove WebView around
                    .transition(.opacity)
            }
        }
        // When the JS bridge tells us the user logged out from the ERPNext UI,
        // pop back to the landing screen.
        .onReceive(NotificationCenter.default.publisher(for: .asawaLogout)) { _ in
            router.destination = .landing
        }
        .animation(.easeInOut(duration: 0.2), value: router.destination)
    }
}
