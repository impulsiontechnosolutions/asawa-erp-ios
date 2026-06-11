//
//  AppDelegate.swift
//  AsawaERP
//
//  Minimal UIKit AppDelegate adapter for our SwiftUI App. We keep one here
//  because several iOS subsystems (background URLSession completion,
//  remote-notification registration, etc.) hook in here, not in SwiftUI.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    // Called once when the app process is launched.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Kick the version-check on launch. Same as Android's checkForForceUpdate().
        // It's fire-and-forget; the UI will surface an alert if an update is needed.
        VersionChecker.shared.checkOnLaunch()

        // Start (or re-start) the significant-location reporter, if user has
        // previously granted "Always" permission. If not, no-op until they do.
        LocationReporter.shared.startIfAuthorized()

        return true
    }

    // Called when the system delivers a background URL session result.
    // We keep a handler list in DownloadHelper so it can finalize the file move.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadHelper.shared.backgroundCompletionHandler = completionHandler
    }
}
