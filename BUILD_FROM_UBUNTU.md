# Building Asawa ERP iOS from Ubuntu 24.04

You can't compile iOS apps on Linux. But you also don't strictly *need* a
Mac on your desk — you can do the entire workflow with cloud-hosted Macs.

Below is the cheapest, slowest path that actually gets to an iPhone screen.

---

## Reality check: what is impossible from Ubuntu alone

| Task | Possible from Ubuntu? |
|---|---|
| Edit Swift source files | ✅ yes (VS Code with Swift extension works fine) |
| Compile `.swift` into a Mach-O binary | ✅ yes — Swift for Linux exists |
| Compile into an **iOS** binary using the **iOS SDK** | ❌ no — the iOS SDK is Apple-licensed and Mac-only |
| Run iOS Simulator | ❌ no |
| Sign an `.ipa` with a Developer certificate | ❌ no — `codesign` is macOS-only |
| Install an unsigned `.app` on an iPhone | ❌ no — Apple requires signing |

Conclusion: you need a Mac **somewhere in the pipeline**. The cheapest version
of "somewhere" is a GitHub-hosted macOS runner billed by the minute.

---

## Step-by-step: GitHub Actions cloud build, no Mac on your desk

### 1. Push this folder to GitHub

```bash
cd AsawaERP-iOS
git init
git add .
git commit -m "Initial commit: iOS WKWebView wrapper for Asawa ERP"
git branch -M main
git remote add origin git@github.com:YOUR_USER/asawa-erp-ios.git
git push -u origin main
```

The `.github/workflows/ios-build.yml` file is already in this folder; GitHub
will pick it up automatically and run a build on every push.

### 2. Watch the first build

- Open your repo on github.com → **Actions** tab.
- The "iOS Build" workflow will be running.
- After ~3 minutes you'll have a green check and an **Artifacts** section
  containing `AsawaERP-Simulator-app`. This is an **iOS Simulator build** —
  it cannot be installed on a real iPhone, but it confirms the code compiles
  cleanly and is a real CI signal.

### 3. (Optional) Run the simulator build remotely

If you ever need to actually *see* the app running before paying for a
Developer Program:

- Rent a Mac for an hour via [MacInCloud](https://www.macincloud.com) (~$1/hr)
  or [MacStadium](https://www.macstadium.com).
- Download the Artifact from GitHub.
- Drag the `.app` into the iOS Simulator (`xcrun simctl install booted AsawaERP.app`).

This costs about $1 and lets you click through the app in the Simulator.

### 4. When you're ready to install on a physical iPhone

**You need an Apple Developer Program account ($99/year).** There's no honest
way around this for an iPhone-installable build without a local Mac.

Once you have the account:

1. Generate an App Store Connect API key (Users and Access → Keys).
   You'll get a `.p8` file, an Issuer ID, and a Key ID.
2. Generate an `ExportOptions.plist` (one-time, contents documented at
   <https://help.apple.com/xcode/mac/current/#/dev1bf96f17e>).
3. Add these as GitHub repo Secrets (Settings → Secrets and variables → Actions):

   | Name | Value |
   |---|---|
   | `APPLE_TEAM_ID` | The 10-character team ID from your developer account |
   | `APPLE_API_KEY_ID` | The 10-character Key ID from step 1 |
   | `APPLE_API_ISSUER_ID` | The Issuer ID UUID from step 1 |
   | `APPLE_API_KEY_P8` | The `.p8` file contents, base64-encoded |
   | `EXPORT_OPTIONS_PLIST` | The plist file contents (XML) |

4. Open `.github/workflows/ios-build.yml`, uncomment the `archive:` job at the
   bottom, commit, push.
5. The next push to `main` will produce a signed `.ipa` and upload it to
   TestFlight. Apple processes the build (~10 min), then you can invite
   yourself as a tester and install it from the TestFlight iPhone app.

From this point on you do **everything from Ubuntu**: edit code, push, get
TestFlight build. No Mac needed.

---

## Editing Swift from VS Code on Ubuntu

If you want decent autocomplete and syntax highlighting without buying JetBrains:

1. Install the official Swift toolchain for Linux: <https://www.swift.org/download/>
   (~600 MB; gives you `swift`, `swiftc`, and `sourcekit-lsp`).
2. In VS Code, install the **Swift** extension by the Swift Server Work Group.
3. Open the `AsawaERP-iOS/` folder. Autocomplete and red-squiggle errors
   work for pure Swift code.
4. Code that imports `WebKit`, `UIKit`, `SwiftUI`, `CoreLocation` will show
   missing-module errors on Linux — those modules only exist in the iOS SDK.
   **Ignore those errors locally.** Push to GitHub; the macOS runner will
   compile fine because it has the iOS SDK.

A common workflow:

```bash
# Edit code locally
code AsawaERP-iOS/AsawaERP/WebView/WebViewController.swift

# Commit & push
git add -A && git commit -m "Tweak file-download MIME list" && git push

# Watch CI on github.com/YOUR_USER/asawa-erp-ios/actions
# If green, download the artifact / wait for TestFlight email.
```

---

## Quick FAQ

**Q: Can I use a Hackintosh or VirtualBox-on-macOS?**
A: Technically yes; against Apple's licensing terms; fragile and not worth the headache for a production app.

**Q: Can I cross-compile with the Theos / iOSOpenDev toolchain?**
A: Only for jailbroken devices. Not viable for the App Store or normal users.

**Q: Why is XcodeGen in here instead of a checked-in `.xcodeproj`?**
A: `.xcodeproj` is a folder containing a near-binary file that Xcode owns and
rewrites constantly. It diffs horribly and merge-conflicts on every change.
`project.yml` is plain YAML you can edit from any OS, and `xcodegen generate`
re-creates the `.xcodeproj` on demand. The result is identical.

**Q: How do I add a new file?**
A: Drop it under the right folder in `AsawaERP/`. Next time you (or CI) run
`xcodegen generate`, it'll be picked up automatically — no manual project
editing needed.

**Q: How do I change the app icon?**
A: Replace `AsawaERP/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
with a 1024×1024 PNG of your real icon. That's it; Xcode 14+ auto-derives all
the smaller sizes from this single image.
