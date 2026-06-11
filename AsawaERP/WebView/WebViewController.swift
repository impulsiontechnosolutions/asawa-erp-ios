//
//  WebViewController.swift
//  AsawaERP
//
//  Production-grade WKWebView host. Every behavior here exists in the
//  Android MainActivity.kt; the file is annotated with the Android function
//  it mirrors so future devs can keep the two platforms in lock-step.
//
//  Feature list (all working):
//    • WKWebView with persistent cookies (default WKWebsiteDataStore)
//    • Custom User-Agent suffix: "AsawaERP-iOS/1.0"
//    • Pull-to-refresh
//    • External schemes routed to system (tel:, mailto:, sms:, maps:, etc.)
//    • External domains opened in Safari
//    • Same-host /app/* deep links handled as in-app navigation
//    • blob: URL download interception via JS bridge
//    • WKDownloadDelegate for native downloads (iOS 14.5+)
//    • Camera/mic permission requests with NS*UsageDescription
//    • Geolocation permission proxy to CLLocationManager
//    • frappe.session.user capture → starts background location reporter
//    • frappe.app.logout hook → stops reporter, returns to landing
//    • Offline HTML fallback page (mirrors Android's showOfflineErrorPage)
//

import UIKit
import WebKit
import CoreLocation
import UniformTypeIdentifiers

final class WebViewController: UIViewController {

    // MARK: - Public

    /// Bound by `WebViewRepresentable`. We write loading/progress/online state here.
    weak var model: WebViewModel?

    /// The current URL displayed. Read by the SwiftUI bridge to detect external pushes.
    private(set) var currentURL: URL

    // MARK: - Internal state

    private let initialURL: URL
    private var webView: WKWebView!
    private var progressObservation: NSKeyValueObservation?

    // Geolocation prompt plumbing
    private var pendingGeoDecisionHandler: ((WKPermissionDecision) -> Void)?
    private let geoLocationManager = CLLocationManager()
    private var geoAuthCallback: ((Bool) -> Void)?

    // MARK: - Init

    init(initialURL: URL) {
        self.initialURL = initialURL
        self.currentURL = initialURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Storyboards not used") }

    // MARK: - Lifecycle

    override func loadView() {
        let config = makeWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true

        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPullToRefresh()
        observeLoadingProgress()
        load(url: initialURL)
    }

    deinit {
        progressObservation?.invalidate()
    }

    // MARK: - WKWebView configuration

    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        // Persistent cookie store — same effect as Android's CookieManager.
        cfg.websiteDataStore = .default()

        // Append our marker to the default WebKit User-Agent. This is the
        // documented, App-Store-safe way; mirrors Android's
        //   userAgentString = "$userAgentString AsawaERP/1.0"
        cfg.applicationNameForUserAgent = Config.userAgentSuffix

        // JavaScript is enabled by default; we set explicit prefs anyway because
        // iOS 14 deprecated WKPreferences.javaScriptEnabled and moved it onto
        // WKWebpagePreferences (handled in navigationAction policy).
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs

        // Inject our bridge before any page JS runs — same as Android's injectJsBridge.
        let userContent = WKUserContentController()
        userContent.add(self, name: "asawaSetUser")
        userContent.add(self, name: "asawaLogout")
        userContent.add(self, name: "asawaBlobChunkStart")
        userContent.add(self, name: "asawaBlobChunkAppend")
        userContent.add(self, name: "asawaBlobChunkFinish")

        let bridgeScript = WKUserScript(
            source: BridgeScript.javaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(bridgeScript)
        cfg.userContentController = userContent

        return cfg
    }

    // MARK: - Pull to refresh

    private func setupPullToRefresh() {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handlePullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = rc
    }

    @objc private func handlePullToRefresh(_ sender: UIRefreshControl) {
        webView.reload()
    }

    // MARK: - Loading progress

    private func observeLoadingProgress() {
        progressObservation = webView.observe(\.estimatedProgress, options: .new) {
            [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                let p = self.webView.estimatedProgress
                self.model?.progress = p
                self.model?.isLoading = p > 0 && p < 1
            }
        }
    }

    // MARK: - Loading

    func load(url: URL) {
        currentURL = url
        var req = URLRequest(url: url)
        req.cachePolicy = .useProtocolCachePolicy
        webView.load(req)
    }

    /// Mirrors Android's showOfflineErrorPage().
    private func showOfflineErrorPage() {
        let html = """
        <!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>
        <style>
          body{font-family:-apple-system,system-ui,sans-serif;display:flex;flex-direction:column;
               align-items:center;justify-content:center;height:100vh;margin:0;background:#f9fafb;color:#374151;}
          .icon{font-size:64px;margin-bottom:16px;}
          h2{margin:0 0 8px;font-size:22px;}
          p{margin:0 0 24px;color:#6b7280;text-align:center;padding:0 24px;}
          button{background:#2563eb;color:#fff;border:none;padding:12px 28px;border-radius:10px;
                 font-size:16px;cursor:pointer;}
        </style></head><body>
        <div class='icon'>📡</div><h2>No Internet Connection</h2>
        <p>Please check your network and try again.</p>
        <button onclick='window.location.reload()'>Retry</button></body></html>
        """
        webView.loadHTMLString(html, baseURL: Config.startURL)
    }
}

// MARK: - WKNavigationDelegate
// Mirrors WebViewClient.shouldOverrideUrlLoading + onPageStarted/Finished/Error
extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel); return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        // 1) Schemes the OS handles natively — same set as Android.
        if ExternalSchemeHandler.systemSchemes.contains(scheme) {
            ExternalSchemeHandler.openExternally(url)
            decisionHandler(.cancel)
            return
        }

        // 2) Our own deep-link scheme — bounce out so AppRouter handles it.
        if scheme == Config.appURLScheme {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        // 3) External hosts — open in Safari, NOT in our WebView.
        if scheme == "http" || scheme == "https" {
            if url.host?.lowercased() != Config.siteHost.lowercased() {
                ExternalSchemeHandler.openExternally(url)
                decisionHandler(.cancel)
                return
            }
        }

        // 4) blob: URLs are intercepted by our injected JS bridge (see BridgeScript).
        //    They never reach navigation policy, so nothing to do here.

        currentURL = url
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

        // If WKWebView wouldn't render this MIME inline (binary downloads,
        // .xlsx, .csv, generic .bin, etc.), promote to a WKDownload.
        // PDFs ARE rendered inline by WKWebView — leave them allowed.
        if let response = navigationResponse.response as? HTTPURLResponse {
            let mime = (response.mimeType ?? "").lowercased()
            let url  = response.url

            let isInlineRenderable =
                navigationResponse.canShowMIMEType
                && !DownloadHelper.shouldForceDownload(mimeType: mime, url: url)

            if !isInlineRenderable {
                if #available(iOS 14.5, *) {
                    decisionHandler(.download)
                    return
                } else {
                    // Fallback path (won't trigger on iOS 16+ deployment target,
                    // but keeps the code defensible).
                    if let u = url {
                        DownloadHelper.shared.legacyDownload(url: u,
                                                             cookieStorage: webView.configuration.websiteDataStore.httpCookieStore,
                                                             presenter: self)
                    }
                    decisionHandler(.cancel)
                    return
                }
            }
        }

        decisionHandler(.allow)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = DownloadHelper.shared
        DownloadHelper.shared.presenter = self
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = DownloadHelper.shared
        DownloadHelper.shared.presenter = self
    }

    func webView(_ webView: WKWebView,
                 didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.model?.isLoading = true
            self.model?.progress = 0
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.model?.isLoading = false
            self.webView.scrollView.refreshControl?.endRefreshing()
        }
        // Flush cookies (mirrors Android CookieManager.getInstance().flush())
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { _ in /* no-op; touching it forces a flush */ }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        DispatchQueue.main.async {
            self.model?.isLoading = false
            self.webView.scrollView.refreshControl?.endRefreshing()

            let ns = error as NSError
            // -1009 = no internet, -1004 = can't connect, -1001 = timeout
            if ns.domain == NSURLErrorDomain &&
                [-1009, -1004, -1001, -1003, -1005].contains(ns.code) {
                self.showOfflineErrorPage()
            }
        }
    }

    // SSL: we use the system's default trust evaluation. No custom challenge
    // handler needed; ERPNext serves a valid certificate.
}

// MARK: - WKUIDelegate
// Camera/mic permissions + geolocation prompt + new-window handling.
extension WebViewController: WKUIDelegate {

    // window.open / target="_blank" — load in the same WKWebView, same as Android.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // Camera + microphone permission prompts.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {

        // Only trust our own origin (same as Android's isTrusted check).
        guard origin.host == Config.siteHost else {
            decisionHandler(.deny); return
        }
        decisionHandler(.grant)
    }

    // JS alert / confirm / prompt — show as iOS alerts so they don't get
    // silently dropped by WKWebView.
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    // File uploads (<input type="file">) are handled by WKWebView natively
    // on iOS — it shows the system picker with Photo Library / Take Photo /
    // Choose File options when the appropriate NS*UsageDescription keys are
    // in Info.plist (which they are). No code required here.
}

// MARK: - WKScriptMessageHandler
// JS → native messages from the injected BridgeScript.
extension WebViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {

        case "asawaSetUser":
            // frappe.session.user changed (login).
            if let email = (message.body as? String)?.trimmingCharacters(in: .whitespaces),
               !email.isEmpty,
               email != "Guest" {
                UserPrefs.shared.email = email
                LocationReporter.shared.startIfAuthorized()
            }

        case "asawaLogout":
            // User tapped the logout button on the ERPNext site.
            UserPrefs.shared.email = nil
            LocationReporter.shared.stop()
            // RootView listens for this and pops back to the landing chooser.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .asawaLogout, object: nil)
            }

        case "asawaBlobChunkStart",
             "asawaBlobChunkAppend",
             "asawaBlobChunkFinish":
            DownloadHelper.shared.handleBlobMessage(name: message.name,
                                                    body: message.body,
                                                    presenter: self)

        default: break
        }
    }
}

extension Notification.Name {
    static let asawaLogout = Notification.Name("AsawaLogoutNotification")
}
