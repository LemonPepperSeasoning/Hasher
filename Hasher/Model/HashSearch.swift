//
//  HashSearch.swift
//  Hasher
//

import Foundation

/// Runs a `DistinguishedPointSearch` from a private serial queue, with one walker per CPU core
/// or thousands on the GPU, publishes progress on the main thread, and saves the search so it
/// survives pauses and relaunches.
final class HashSearch: ObservableObject {

    static let bitOptions = [24, 32, 40, 48, 56, 64, 80, 128, 256]
    static let defaultBits = 256

    @Published private(set) var bits: Int
    @Published private(set) var count: UInt64
    @Published private(set) var hashesPerSecond: Double = 0
    @Published private(set) var isComputing = false
    @Published private(set) var walkers: Int
    @Published private(set) var storedPoints: Int
    @Published private(set) var collision: Collision?
    @Published private(set) var usesGPU: Bool
    let isGPUAvailable = GPUWalker.isSupported

    /// How long all walkers run between progress updates.
    private static let roundSeconds = 0.05
    private static let storageKey = "HashSearch.dp.v2"
    private static let usesGPUKey = "HashSearch.usesGPU"

    // `search` is only touched on `queue`.
    private let queue = DispatchQueue(label: "Hasher.HashSearch", qos: .userInitiated)
    private var search: DistinguishedPointSearch
    private var gpu: GPUWalker?
    private let defaults: UserDefaults
    // Bumped synchronously on every start/stop, so queued or in-flight work from an earlier run is dropped.
    private let generationLock = NSLock()
    private var generation = 0

    private var rateSample: (time: Date, count: UInt64)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey).flatMap { try? PropertyListDecoder().decode(DistinguishedPointSearch.self, from: $0) }
        let search = saved ?? Self.makeSearch(bits: Self.defaultBits)
        self.search = search
        usesGPU = isGPUAvailable && defaults.bool(forKey: Self.usesGPUKey)
        bits = search.step.bits
        count = search.hashes
        walkers = search.walkers.count
        storedPoints = search.points.count
        collision = search.collision
    }

    /// CPU and GPU walkers share one search, so its trail length must suit the GPU when there is one.
    private static func makeSearch(bits: Int) -> DistinguishedPointSearch {
        let step = HashStep(bits: bits)
        let walkers = ProcessInfo.processInfo.activeProcessorCount
        let dpBits = GPUWalker.isSupported ? GPUWalker.dpBits(bits: bits) : nil
        return DistinguishedPointSearch(step: step, walkers: walkers, dpBits: dpBits)
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
        let onGPU = usesGPU
        queue.async { [weak self] in
            self?.runBatch(generation: generation, onGPU: onGPU)
        }
    }

    /// Switches between CPU and GPU walkers. Only allowed while paused.
    func setUsesGPU(_ usesGPU: Bool) {
        guard !isComputing, isGPUAvailable else { return }
        self.usesGPU = usesGPU
        defaults.set(usesGPU, forKey: Self.usesGPUKey)
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
        storedPoints = 0
        bumpGeneration()
        queue.async { [weak self] in
            guard let self else { return }
            self.search = Self.makeSearch(bits: bits)
            self.gpu = nil
            self.persist()
        }
    }

    func save() {
        queue.async { [weak self] in
            self?.persist()
        }
    }

    private func persist() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(search) {
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

    private func runBatch(generation: Int, onGPU: Bool) {
        guard isCurrent(generation) else { return }

        let found: Collision?
        if onGPU, let gpu = gpuWalker() {
            let result = gpu.run(seconds: Self.roundSeconds)
            found = search.absorb(result.found, hashes: result.hashes)
        } else {
            found = search.run(seconds: Self.roundSeconds)
        }
        let count = search.hashes
        let storedPoints = search.points.count
        if found != nil {
            persist()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.count = count
            self.storedPoints = storedPoints
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
                self?.runBatch(generation: generation, onGPU: onGPU)
            }
        }
    }

    /// The GPU walkers for the current search, created on first use.
    private func gpuWalker() -> GPUWalker? {
        if gpu?.step != search.step {
            gpu = GPUWalker(step: search.step, dpBits: search.dpBits, maxTrailLength: search.maxTrailLength)
        }
        return gpu
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
