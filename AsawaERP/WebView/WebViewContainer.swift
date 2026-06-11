//
//  WebViewContainer.swift
//  AsawaERP
//
//  SwiftUI shell around the UIKit `WebViewController`. Adds:
//    • Top progress bar (mirrors Android's pageProgress)
//    • Offline banner (mirrors Android's offlineBanner)
//    • Pull-to-refresh (handled inside WebViewController)
//

import SwiftUI

struct WebViewContainer: View {
    let initialURL: URL

    @StateObject private var model = WebViewModel()
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack(alignment: .top) {

            WebViewRepresentable(model: model, initialURL: initialURL)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                // Page-load progress
                if model.isLoading {
                    ProgressView(value: model.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(height: 3)
                        .transition(.opacity)
                }

                // Offline banner
                if !model.isOnline {
                    Text("⚠️  No internet connection — showing cached content")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.isLoading)
            .animation(.easeInOut(duration: 0.2), value: model.isOnline)
        }
        .alert("Update Required",
               isPresented: $model.showForceUpdate,
               actions: {
                   Button("Update Now") { model.openAppStoreForUpdate() }
               },
               message: {
                   Text(model.forceUpdateMessage)
               })
    }
}
