//
//  HashSearch.swift
//  Hasher
//

import Foundation

/// Runs a `RhoSearch` on a private serial queue, publishes progress on the main thread,
/// and saves the search so it survives pauses and relaunches.
final class HashSearch: ObservableObject {

    static let bitOptions = [24, 32, 40, 48, 56, 64, 80, 128, 256]
    static let defaultBits = 256

    @Published private(set) var bits: Int
    @Published private(set) var count: UInt64
    @Published private(set) var hashesPerSecond: Double = 0
    @Published private(set) var isComputing = false
    @Published private(set) var phase: RhoSearch.Phase
    @Published private(set) var collision: Collision?

    private static let batchSize = 50_000
    private static let storageKey = "HashSearch.rho.v1"

    // `search` is only touched on `queue`.
    private let queue = DispatchQueue(label: "Hasher.HashSearch", qos: .userInitiated)
    private var search: RhoSearch
    private let defaults: UserDefaults
    // Bumped synchronously on every start/stop, so queued or in-flight work from an earlier run is dropped.
    private let generationLock = NSLock()
    private var generation = 0

    private var rateSample: (time: Date, count: UInt64)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(RhoSearch.self, from: $0) }
        let search = saved ?? RhoSearch(bits: Self.defaultBits)
        self.search = search
        bits = search.step.bits
        count = search.hashes
        phase = search.phase
        collision = search.collision
    }

    /// Expected hashes for a birthday-style search over `bits` bits: √(πN/2).
    static func expectedHashes(bits: Int) -> Double {
        (Double.pi / 2).squareRoot() * pow(2, Double(bits) / 2)
    }

    func toggle() {
        isComputing ? pause() : start()
    }

    func start() {
        guard !isComputing else { return }
        if collision != nil {
            newSearch(bits: bits)
        }
        isComputing = true
        rateSample = nil
        let generation = bumpGeneration()
        queue.async { [weak self] in
            self?.runBatch(generation: generation)
        }
    }

    func pause() {
        guard isComputing else { return }
        isComputing = false
        hashesPerSecond = 0
        bumpGeneration()
        save()
    }

    /// Starts over with a fresh salt. Only allowed while paused.
    func newSearch(bits: Int) {
        guard !isComputing else { return }
        self.bits = bits
        count = 0
        collision = nil
        phase = .findCycle
        bumpGeneration()
        queue.async { [weak self] in
            guard let self else { return }
            self.search = RhoSearch(bits: bits)
            self.persist()
        }
    }

    func save() {
        queue.async { [weak self] in
            self?.persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(search) {
            defaults.set(data, forKey: Self.storageKey)
        }
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

        let found = search.run(maxHashes: Self.batchSize)
        let count = search.hashes
        let phase = search.phase
        if found != nil {
            persist()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.count = count
            self.phase = phase
            self.updateRate(count: count)
            if let found {
                self.collision = found
                self.isComputing = false
                self.hashesPerSecond = 0
            }
        }

        if found == nil {
            // Re-enqueue instead of looping so pause/start get a turn on the queue between batches.
            queue.async { [weak self] in
                self?.runBatch(generation: generation)
            }
        }
    }

    private func updateRate(count: UInt64) {
        let now = Date()
        guard let sample = rateSample else {
            rateSample = (now, count)
            return
        }
        let elapsed = now.timeIntervalSince(sample.time)
        guard elapsed >= 0.5, count >= sample.count else { return }
        hashesPerSecond = Double(count - sample.count) / elapsed
        rateSample = (now, count)
    }
}
