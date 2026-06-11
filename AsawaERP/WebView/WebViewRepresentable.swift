//
//  WebViewRepresentable.swift
//  AsawaERP
//
//  SwiftUI <-> UIKit bridge around the `WebViewController`.
//
//  IMPORTANT: do NOT reload the WebView every time SwiftUI re-renders us.
//  SwiftUI calls updateUIViewController on every published-property change
//  (every isLoading flip, every offline toggle, etc.). If we compare against
//  the WebView's *current* URL (which changes constantly during ERPNext
//  redirects to /login etc.), we end up canceling and restarting the
//  navigation forever — the page never finishes loading, the user sees a
//  blank white screen.
//
//  We use a Coordinator to remember the LAST URL SwiftUI handed us. We only
//  reload when SwiftUI hands us a *different* URL — which only happens when
//  the user backs out to the landing screen and re-enters the WebView, or a
//  deep link routes them somewhere specific.
//

import SwiftUI

struct WebViewRepresentable: UIViewControllerRepresentable {

    @ObservedObject var model: WebViewModel
    let initialURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(lastDeliveredURL: initialURL)
    }

    func makeUIViewController(context: Context) -> WebViewController {
        let vc = WebViewController(initialURL: initialURL)
        vc.model = model
        return vc
    }

    func updateUIViewController(_ uiViewController: WebViewController,
                                context: Context) {
        // Only act when SwiftUI gives us a brand-new URL that differs from
        // the last one we accepted. Internal WebView navigation is NOT a
        // trigger to reload — that's what the WebView is for.
        if context.coordinator.lastDeliveredURL != initialURL {
            context.coordinator.lastDeliveredURL = initialURL
            uiViewController.load(url: initialURL)
        }
    }

    /// Tracks the most recent URL SwiftUI asked us to load.
    final class Coordinator {
        var lastDeliveredURL: URL
        init(lastDeliveredURL: URL) {
            self.lastDeliveredURL = lastDeliveredURL
        }
    }
}
