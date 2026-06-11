//
//  DownloadHelper.swift
//  AsawaERP
//
//  Handles every kind of download the WKWebView can throw at us:
//
//   1. Regular HTTP downloads (xlsx, csv, zip, etc.) → WKDownloadDelegate
//      saves to a temporary file then presents a Share Sheet so the user
//      can move it to Files / Mail / iCloud / etc.
//
//   2. blob: URLs → reassembled from base64 chunks delivered by our
//      injected JS (BridgeScript). Same end-game: Share Sheet.
//
//   3. Legacy path (iOS < 14.5) → URLSession fallback. Our deployment
//      target is iOS 16, so this branch is dead code, but it's kept so
//      the file compiles cleanly if anyone lowers the target later.
//
//  On Android the equivalent is DownloadManager + okHttpDownloadToDownloads
//  + the AndroidBridge chunked-file methods.
//

import UIKit
import WebKit
import UniformTypeIdentifiers

final class DownloadHelper: NSObject {

    static let shared = DownloadHelper()

    /// Set by AppDelegate when a background URLSession event arrives.
    var backgroundCompletionHandler: (() -> Void)?

    /// Whoever should present the Share Sheet.
    weak var presenter: UIViewController?

    // ── Blob reassembly state ─────────────────────────────────────────
    private struct BlobJob {
        let filename: String
        let mime: String
        let totalChunks: Int
        var receivedChunks: [Int: Data] = [:]   // index → bytes
    }
    private var blobJobs: [String: BlobJob] = [:]   // token → job
    private let blobQueue = DispatchQueue(label: "asawa.blob.queue")

    // MARK: - Heuristics

    /// MIMEs we never want to render inline — force download even if WKWebView
    /// claims it can show them. Mirrors Android's same-origin export detection.
    static func shouldForceDownload(mimeType: String, url: URL?) -> Bool {
        let m = mimeType.lowercased()
        let forced: Set<String> = [
            "application/octet-stream",
            "application/zip",
            "application/x-zip-compressed",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "text/csv"
        ]
        if forced.contains(m) { return true }

        if let u = url?.absoluteString.lowercased() {
            // Frappe export URLs typically end with format= queries or contain /api/method/.../get_file
            if u.contains("format=csv") || u.contains("format=xlsx") ||
               u.contains("format=excel") || u.contains("file_url=") ||
               u.contains("/private/files/") || u.contains("/files/") &&
                 (u.hasSuffix(".xlsx") || u.hasSuffix(".csv") || u.hasSuffix(".zip")) {
                return true
            }
        }
        return false
    }

    // MARK: - Blob (JS bridge) flow

    func handleBlobMessage(name: String, body: Any, presenter: UIViewController) {
        self.presenter = presenter

        switch name {
        case "asawaBlobChunkStart":
            guard let dict = body as? [String: Any],
                  let token = dict["token"] as? String,
                  let filename = dict["filename"] as? String,
                  let mime = dict["mime"] as? String,
                  let total = dict["totalChunks"] as? Int else { return }
            blobQueue.sync {
                blobJobs[token] = BlobJob(filename: sanitizeFileName(filename),
                                          mime: mime,
                                          totalChunks: total)
            }

        case "asawaBlobChunkAppend":
            guard let dict = body as? [String: Any],
                  let token = dict["token"] as? String,
                  let index = dict["index"] as? Int,
                  let base64 = dict["base64"] as? String,
                  let data = Data(base64Encoded: base64) else { return }
            blobQueue.sync {
                blobJobs[token]?.receivedChunks[index] = data
            }

        case "asawaBlobChunkFinish":
            guard let dict = body as? [String: Any],
                  let token = dict["token"] as? String else { return }

            let jobOpt: BlobJob? = blobQueue.sync { blobJobs.removeValue(forKey: token) }
            guard let job = jobOpt else { return }

            // Reassemble in order.
            var assembled = Data()
            for i in 0..<job.totalChunks {
                guard let chunk = job.receivedChunks[i] else {
                    showToast("Download incomplete: missing chunk \(i)")
                    return
                }
                assembled.append(chunk)
            }
            persistAndShare(data: assembled,
                            filename: job.filename,
                            mime: job.mime)

        default: break
        }
    }

    // MARK: - WKDownload flow (iOS 14.5+)

    /// Tracks per-WKDownload destination URL during the download lifecycle.
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private let downloadQueue = DispatchQueue(label: "asawa.download.queue")

    // MARK: - Common: save to temp + present Share Sheet

    private func persistAndShare(data: Data, filename: String, mime: String) {
        let safeName = sanitizeFileName(filename)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsawaDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            presentShareSheet(for: url)
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    private func presentShareSheet(for url: URL) {
        DispatchQueue.main.async {
            guard let vc = self.presenter ?? UIApplication.topMostViewController() else {
                return
            }
            let share = UIActivityViewController(activityItems: [url],
                                                  applicationActivities: nil)
            // Pad to avoid iPad crashes when no popover anchor is set.
            if let pop = share.popoverPresentationController {
                pop.sourceView = vc.view
                pop.sourceRect = CGRect(x: vc.view.bounds.midX,
                                        y: vc.view.bounds.maxY - 40,
                                        width: 0, height: 0)
            }
            vc.present(share, animated: true)
        }
    }

    private func showToast(_ message: String) {
        DispatchQueue.main.async {
            guard let vc = self.presenter ?? UIApplication.topMostViewController() else { return }
            let alert = UIAlertController(title: nil, message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            vc.present(alert, animated: true)
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "_")
        return cleaned.isEmpty ? "download" : cleaned
    }

    // MARK: - Legacy fallback (only used on iOS < 14.5; unused for our iOS 16 target)

    func legacyDownload(url: URL,
                        cookieStorage: WKHTTPCookieStore,
                        presenter: UIViewController) {
        self.presenter = presenter
        cookieStorage.getAllCookies { cookies in
            var request = URLRequest(url: url)
            let header = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in header { request.setValue(v, forHTTPHeaderField: k) }
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                if let error = error {
                    self.showToast("Download error: \(error.localizedDescription)"); return
                }
                guard let data = data else {
                    self.showToast("Download failed (empty body)"); return
                }
                let mime = (response?.mimeType ?? "application/octet-stream").lowercased()
                // Parenthesize explicitly — Swift's `??` has higher precedence
                // than the ternary operator, so without these parens this would
                // parse as `(suggestedFilename ?? isEmpty) ? "download" : ...`.
                let name = response?.suggestedFilename
                    ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
                self.persistAndShare(data: data, filename: name, mime: mime)
            }.resume()
        }
    }
}

// MARK: - WKDownloadDelegate (iOS 14.5+)

@available(iOS 14.5, *)
extension DownloadHelper: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsawaDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)

        let safeName = sanitizeFileName(suggestedFilename.isEmpty ? "download" : suggestedFilename)
        let destination = dir.appendingPathComponent(safeName)
        // WKDownload requires the file NOT to exist yet.
        try? FileManager.default.removeItem(at: destination)

        downloadQueue.sync {
            downloadDestinations[ObjectIdentifier(download)] = destination
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let dest: URL? = downloadQueue.sync {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        }
        if let dest { presentShareSheet(for: dest) }
    }

    func download(_ download: WKDownload,
                  didFailWithError error: Error,
                  resumeData: Data?) {
        downloadQueue.sync {
            _ = downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        }
        showToast("Download failed: \(error.localizedDescription)")
    }
}

// MARK: - Small UI helper

extension UIApplication {
    static func topMostViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let sel = tab.selectedViewController {
            return topMostViewController(base: sel)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
