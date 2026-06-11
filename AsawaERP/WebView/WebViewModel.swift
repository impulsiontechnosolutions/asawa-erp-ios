//
//  WebViewModel.swift
//  AsawaERP
//
//  Observable state shared between the SwiftUI container and the
//  UIKit WebViewController. The UIViewController writes to these fields;
//  SwiftUI reacts.
//

import Foundation
import UIKit
import Combine

@MainActor
final class WebViewModel: ObservableObject {

    // Network / loading state
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0     // 0…1
    @Published var isOnline: Bool = true

    // Force-update state
    @Published var showForceUpdate: Bool = false
    @Published var forceUpdateMessage: String =
        "A new version of Asawa ERP is required to continue."
    @Published var updateURL: URL? = nil

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to Reachability for online/offline updates.
        Reachability.shared.start()
        Reachability.shared.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online in
                self?.isOnline = online
            }
            .store(in: &cancellables)

        // Subscribe to VersionChecker's force-update notifications.
        VersionChecker.shared.$forceUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self, let info else { return }
                self.forceUpdateMessage = info.message
                self.updateURL = info.updateURL
                self.showForceUpdate = true
            }
            .store(in: &cancellables)
    }

    func openAppStoreForUpdate() {
        if let url = updateURL {
            UIApplication.shared.open(url)
        }
    }
}
