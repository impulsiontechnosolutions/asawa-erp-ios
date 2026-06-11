# Asawa ERP — iOS

iPhone version of the **Asawa ERP** Android app. This is a **WKWebView wrapper** around
`https://erp.asawainsulation.com`, mirroring the Android app's behavior almost line-for-line.

| Item | Value |
|---|---|
| **Bundle ID** | `com.asawa.erp` |
| **Min iOS** | 16.0 (covers iPhone 11+; required for iPhone 14+) |
| **Target devices** | iPhone only |
| **Language** | Swift 5.9 |
| **UI** | SwiftUI shell + UIKit `WKWebView` host |
| **Build tool** | XcodeGen (`project.yml`) → produces `.xcodeproj` |

---

## What the app does (feature parity with Android)

| Capability | Android source | iOS source |
|---|---|---|
| Landing screen with ERP + Raven cards | `LandingActivity.kt` | `LandingView.swift` |
| WKWebView with persistent cookies | `MainActivity.setupWebView` | `WebViewController.swift` |
| Custom User-Agent | `MainActivity.kt:271` | `WebViewController.loadView` |
| Pull-to-refresh | n/a | `WebViewController.setupPullToRefresh` |
| External schemes (tel/mailto/sms/maps) | `shouldOverrideUrlLoading` | `ExternalSchemeHandler` |
| External hosts open in Safari | same | `decidePolicyFor navigationAction` |
| `asawa-mobile://` deep links | manifest `intent-filter` | `Info.plist` `CFBundleURLTypes` + `AppRouter.handleIncoming` |
| File upload (`<input type="file">`) | `onShowFileChooser` | Native iOS picker (no code needed) |
| File downloads | `okHttpDownloadToDownloads` | `DownloadHelper` + `WKDownloadDelegate` |
| `blob:` URL download interception | `injectJsBridge` + `AndroidBridge` | `BridgeScript` + `DownloadHelper.handleBlobMessage` |
| Login user capture | `frappe.session.user → AndroidBridge.setUser` | `frappe.session.user → asawaSetUser` message |
| Logout hook | `frappe.app.logout` patched | same, via `asawaLogout` message |
| Force-update check | `checkForForceUpdate` → `asawa_get_app_version` | `VersionChecker` (same endpoint) |
| Offline banner | `NetworkMonitor` | `Reachability` (NWPathMonitor) |
| Offline fallback HTML | `showOfflineErrorPage` | `WebViewController.showOfflineErrorPage` |
| Background location → `asawa_log_location` | `LocationWorker` (15-min WorkManager) | `LocationReporter` (significant location changes) |

### What's intentionally NOT in this build yet

- **Firebase / APNs push notifications.** You decided to add these after the
  paid Apple Developer Program is in place (APNs needs that anyway). When
  you're ready, see `LATER_FCM.md` (TODO) or ping me for the integration steps.
- **Universal Links** for `https://erp.asawainsulation.com/app/*`. Requires
  an `apple-app-site-association` file hosted on your domain AND a paid
  developer team. Already stubbed in `AsawaERP.entitlements` — uncomment
  when ready.
- **Raven (Asawa Connect)** is a *placeholder*. The landing card tries
  `asawa-connect://`; if not installed, opens an App Store URL. Update
  `Config.ravenURLScheme` and `Config.ravenAppStoreURL` once the Raven iOS
  app exists.

---

## Building this project — three paths

iOS apps cannot be built on Linux. You're on Ubuntu, so pick one of:

### Path A — Borrow / rent a Mac for an hour (cheapest local test)

Best for: doing the very first install on your physical iPhone using a *free*
Apple ID (no $99/yr needed yet). The app will work for 7 days before needing
to be re-installed from the Mac.

1. Get any Intel or Apple Silicon Mac running macOS 13+.
2. Install Xcode 15+ from the Mac App Store (~10 GB download).
3. Install XcodeGen:
   ```
   brew install xcodegen
   ```
4. Copy this project folder to the Mac, then:
   ```
   cd AsawaERP-iOS
   xcodegen generate
   open AsawaERP.xcodeproj
   ```
5. In Xcode:
   - Select the `AsawaERP` target → **Signing & Capabilities** tab.
   - Tick **Automatically manage signing**.
   - **Team** → "Add an Account…" → sign in with your personal Apple ID.
     (No Developer Program needed for sideloading.)
   - Plug in your iPhone, trust the Mac when prompted.
   - Select your iPhone in the device picker at the top.
   - Press **▶ Run**. The app installs.
   - On the iPhone, go to *Settings → General → VPN & Device Management →
     Developer App → Trust*.
6. App stays installed for 7 days, then has to be rebuilt from Xcode.

### Path B — GitHub Actions cloud build (no Mac needed at all)

Best for: ongoing CI, plus eventually producing signed TestFlight builds.

1. Push this folder to a GitHub repo (private or public).
2. Push triggers `.github/workflows/ios-build.yml`. It will spin up a macOS
   runner, build an unsigned `.app`, and upload it as an artifact.
3. **Unsigned `.app` cannot run on a real iPhone.** It can only run in the
   iOS Simulator, which itself requires a Mac.
4. Once you have an Apple Developer Program account ($99/yr), uncomment the
   "Archive & Upload to TestFlight" job in the workflow file and set the
   listed secrets. Pushes will then auto-deliver TestFlight builds.

**Cost:** free on public repos. On private repos, macOS-runner minutes are
billed at ~$0.08/min (≈$0.30 per build).

### Path C — Codemagic / Bitrise (managed CI with a UI)

Same idea as Path B but with a friendlier dashboard. Codemagic has a free
tier of 500 macOS build minutes/month. Point it at the same repo;
configuration is similar to the GitHub Actions file.

---

## Folder layout

```
AsawaERP-iOS/
├── project.yml                      # XcodeGen spec — defines the project
├── README.md                        # This file
├── BUILD_FROM_UBUNTU.md             # Step-by-step path B walkthrough
├── .gitignore
├── .github/workflows/ios-build.yml  # Cloud build pipeline
└── AsawaERP/
    ├── Info.plist                   # All permission strings + URL schemes
    ├── AsawaERP.entitlements        # Empty for free signing; ready for later
    ├── App/
    │   ├── AsawaERPApp.swift        # @main
    │   ├── AppDelegate.swift        # UIKit hooks
    │   ├── AppRouter.swift          # Landing ↔ WebView state machine
    │   └── Config.swift             # URLs, auth header, app constants
    ├── Views/
    │   ├── RootView.swift           # Top-level switcher
    │   └── LandingView.swift        # ERP + Raven cards
    ├── WebView/
    │   ├── WebViewContainer.swift   # SwiftUI shell (progress, offline)
    │   ├── WebViewRepresentable.swift # SwiftUI↔UIKit bridge
    │   ├── WebViewController.swift  # The actual WKWebView host
    │   ├── WebViewModel.swift       # Observable state
    │   ├── BridgeScript.swift       # Injected JS (login capture, blob hook)
    │   ├── DownloadHelper.swift     # WKDownload + blob reassembly + Share Sheet
    │   ├── ExternalSchemeHandler.swift
    │   └── VersionChecker.swift     # /api/method/asawa_get_app_version
    ├── Location/
    │   └── LocationReporter.swift   # Significant location changes → POST
    ├── Util/
    │   ├── Reachability.swift
    │   └── UserPrefs.swift
    └── Resources/
        ├── LaunchScreen.storyboard
        └── Assets.xcassets/
            ├── AppIcon.appiconset/  # Placeholder blue/white icon
            └── AccentColor.colorset/
```

---

## Testing checklist

Run through these once installed on a device. Each item maps to a specific
piece of code so a failure points you at one file.

### Basic shell
- [ ] App opens to the Landing screen with two cards
- [ ] Tap **Continue to ERP** → WKWebView loads `erp.asawainsulation.com`
- [ ] Tap **Asawa Connect** → tries `asawa-connect://`, falls through to App Store URL
- [ ] Pull down on the WebView → page reloads (refresh control visible)
- [ ] Toggle airplane mode → orange offline banner appears
- [ ] Disable airplane mode → banner disappears, reload works
- [ ] Force-quit and reopen with no internet → offline fallback HTML page shows with Retry

### Login / session
- [ ] Log in via the ERPNext page → app remembers your session next launch (cookies persist)
- [ ] After login, check device logs (Console.app on Mac) for `asawaSetUser` message
- [ ] Log out from the ERPNext UI → `LocationReporter` stops, `UserPrefs.email` cleared

### File operations
- [ ] Attach a file via any "Upload" button on an ERPNext form → iOS picker appears
  with Photo Library / Take Photo / Choose File
- [ ] Export any list as Excel → Share Sheet appears with the .xlsx
- [ ] Export as CSV → Share Sheet with .csv
- [ ] Find a PDF print view → opens inline in the WebView (this is WKWebView default)
- [ ] Trigger any `blob:` URL download (some Frappe report exports do this) →
  Share Sheet with the file

### Permissions
- [ ] Tap any `tel:` link on a Contact → iOS prompts to call
- [ ] Tap any `mailto:` link → Mail composer opens
- [ ] First time scanning a barcode / using camera in a form →
  "Asawa ERP would like to access the camera" prompt with your custom string
- [ ] First time `navigator.geolocation` is used by ERPNext →
  prompt for location with your custom string

### Background location (your "reduced guarantees" path)
- [ ] After login, walk ~500m or wait 10+ minutes →
  one POST to `/api/method/asawa_log_location` per movement event
- [ ] Check ERPNext "Mobile Location Log" doctype — new entries with `provider="ios"`
- [ ] Background the app (don't kill) → keep moving → entries continue
- [ ] Kill the app → entries pause UNLESS the user has granted "Always" location
  (with "Always", iOS may relaunch your app for significant changes)

### Deep links
- [ ] In Safari, paste `asawa-mobile://app/some-doctype` → confirms "Open in Asawa ERP"
  → app launches and navigates to the page

---

## Notes / risks

1. **Hardcoded API token in `Config.swift`.** Same trade-off as Android — anyone
   who unzips the IPA can read it. Same threat model as the Android APK had.
   When you have time, move the location reporter to use the user's cookie
   session instead of a static token.

2. **"Provider" string is `"ios"` on iOS, was `"android"` on Android.** Your
   ERPNext server-script should accept both. If the script currently filters
   `provider == "android"`, update it to accept `"ios"` too.

3. **Background location is best-effort.** iOS does NOT guarantee the 15-minute
   cadence that Android `WorkManager` offered. You'll get updates roughly every
   5 minutes / 500m, and the app can be relaunched after termination ONLY if the
   user grants "Always" permission. Make sure your dashboard doesn't break when
   entries are sparse.

4. **App Store review** of background location is strict. When you submit, expect
   reviewers to ask: "why does Asawa ERP need to know the user's location while
   in the background?" Have a clear answer ready (field-staff attendance, etc.)
   and a video showing the in-app feature that uses it.

5. **First-launch user-agent quirk.** WKWebView only fully respects
   `customUserAgent` on the *next* navigation. So the very first GET to the
   site uses the default WebKit UA; from page 2 onward it includes
   `AsawaERP-iOS/1.0`. If you need it on the first request, we can pre-warm a
   throwaway navigation — let me know and I'll add it.

6. **Raven iOS app does not yet exist.** The "Asawa Connect" button is
   functional but will always fall back to the App Store URL. Once Raven for
   iOS is on the App Store, update `Config.ravenURLScheme` and
   `Config.ravenAppStoreURL`.
