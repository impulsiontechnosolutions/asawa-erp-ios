//
//  LandingView.swift
//  AsawaERP
//
//  Two big tappable cards — exactly mirroring Android's LandingActivity:
//    1) Continue to ERP  →  opens the WKWebView at erp.asawainsulation.com
//    2) Open Asawa Connect (Raven)  →  launches the Raven iOS app if
//       installed, or falls back to App Store (placeholder for now).
//

import SwiftUI

struct LandingView: View {

    @EnvironmentObject private var router: AppRouter
    @State private var versionTapCount: Int = 0
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ZStack {
            // Soft background so the cards pop without screaming gradients.
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 24) {

                // Header
                VStack(spacing: 6) {
                    Text("Asawa ERP")
                        .font(.system(size: 32, weight: .bold))
                    Text("Welcome — pick where you want to go")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // ─── ERP card ───
                LandingCard(
                    title: "Continue to ERP",
                    subtitle: "Open the Asawa ERPNext system",
                    systemImage: "rectangle.stack.fill",
                    tint: .blue
                ) {
                    router.openERP()
                }

                // ─── Raven (Asawa Connect) card ───
                LandingCard(
                    title: "Asawa Connect",
                    subtitle: "Chat with your team (Raven). Opens the Asawa Connect app if installed.",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    tint: .purple
                ) {
                    router.openRaven()
                }

                Spacer()

                // Tap this 7 times to reveal the hidden Diagnostics screen.
                // Same Easter-egg pattern Apple uses in their own apps.
                Text("v\(appVersionString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 7 {
                            versionTapCount = 0
                            showDiagnostics = true
                        }
                    }
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticView()
        }
    }

    private var appVersionString: String {
        let dict = Bundle.main.infoDictionary
        let marketing = dict?["CFBundleShortVersionString"] as? String ?? "?"
        let build = dict?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

// MARK: - Reusable card

private struct LandingCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .semibold))
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.white)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LandingView().environmentObject(AppRouter())
}
