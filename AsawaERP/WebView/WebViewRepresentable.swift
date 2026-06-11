//
//  WebViewRepresentable.swift
//  AsawaERP
//
//  UIViewControllerRepresentable around `WebViewController`. SwiftUI doesn't
//  ship a great WKWebView component yet (file uploads, downloads, geolocation
//  permission prompts and JS message handlers are all easier from UIKit), so
//  we host the controller and pipe state both ways.
//

import SwiftUI

struct WebViewRepresentable: UIViewControllerRepresentable {

    @ObservedObject var model: WebViewModel
    let initialURL: URL

    func makeUIViewController(context: Context) -> WebViewController {
        let vc = WebViewController(initialURL: initialURL)
        vc.model = model
        return vc
    }

    func updateUIViewController(_ uiViewController: WebViewController,
                                context: Context) {
        // If SwiftUI passes a new initial URL while the controller is alive
        // (e.g. router pushed a deep link), navigate to it.
        if uiViewController.currentURL != initialURL {
            uiViewController.load(url: initialURL)
        }
    }
}
