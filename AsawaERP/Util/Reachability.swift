//
//  Reachability.swift
//  AsawaERP
//
//  Thin wrapper around NWPathMonitor. Mirrors the Android NetworkMonitor.
//

import Foundation
import Network

@MainActor
final class Reachability: ObservableObject {

    static let shared = Reachability()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "asawa.reachability")
    private var started = false

    nonisolated init() {}

    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }
}
