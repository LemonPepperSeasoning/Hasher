//
//  HashSearch.swift
//  Hasher
//

import Foundation
import UIKit

/// Runs `HashComputer` on a private serial queue and publishes progress to the UI on the main thread.
final class HashSearch: ObservableObject {

    @Published private(set) var count: UInt64 = 0
    @Published private(set) var isComputing = false
    @Published private(set) var isTableFull = false
    @Published private(set) var collision: Collision?

    private static let batchSize = 20_000

    // `computer` is only touched on `queue`.
    private let queue = DispatchQueue(label: "Hasher.HashSearch", qos: .userInitiated)
    private let computer = HashComputer()
    // Bumped synchronously on every start/stop, so queued or in-flight work from an earlier run is dropped.
    private let generationLock = NSLock()
    private var generation = 0

    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                print("Memory warning: clearing stored hashes")
                self?.computer.clearStoredHashes()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func toggle() {
        isComputing ? pause() : start()
    }

    func start() {
        guard !isComputing else { return }
        isComputing = true
        collision = nil
        let generation = bumpGeneration()
        queue.async { [weak self] in
            self?.runBatch(generation: generation)
        }
    }

    func pause() {
        guard isComputing else { return }
        isComputing = false
        bumpGeneration()
    }

    @discardableResult
    private func bumpGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == self.generation
    }

    private func runBatch(generation: Int) {
        guard isCurrent(generation) else { return }

        var found: Collision?
        for _ in 0..<Self.batchSize {
            if let collision = computer.computeOne() {
                found = collision
                break
            }
        }

        let count = computer.counter
        let isTableFull = computer.isTableFull
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.count = count
            self.isTableFull = isTableFull
            if let found, self.isCurrent(generation) {
                self.collision = found
                self.isComputing = false
            }
        }

        if found == nil {
            // Re-enqueue instead of looping so pause/start get a turn on the queue between batches.
            queue.async { [weak self] in
                self?.runBatch(generation: generation)
            }
        }
    }
}
