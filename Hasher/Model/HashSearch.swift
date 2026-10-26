//
//  HashSearch.swift
//  Hasher
//

import Foundation

/// Runs a `DistinguishedPointSearch` from a private serial queue, with walkers spread across the
/// CPU cores or thousands on the GPU, publishes progress on the main thread, and saves the search so it
/// survives pauses and relaunches. Bits, CPU or GPU, and the seed are fixed for a search; changing
/// any of them starts a new one.
final class HashSearch: ObservableObject {

    static let bitOptions = [24, 32, 40, 48, 56, 64, 80, 128, 256]
    static let defaultBits = 256

    @Published private(set) var bits: Int
    @Published private(set) var usesGPU: Bool
    /// The seed typed in settings. Empty means a random seed for each new search.
    @Published private(set) var seedText: String
    /// The current search's seed, typed or random.
    @Published private(set) var seed: String
    @Published private(set) var count: UInt64
    @Published private(set) var elapsed: Double
    @Published private(set) var hashesPerSecond: Double = 0
    @Published private(set) var isComputing = false
    @Published private(set) var collision: Collision?
    let isGPUAvailable = GPUWalker.isSupported

    /// How long all walkers run between progress updates.
    private static let roundSeconds = 0.05
    private static let storageKey = "HashSearch.dp.v3"
    private static let usesGPUKey = "HashSearch.usesGPU"
    private static let seedKey = "HashSearch.seed"

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
        // Searches saved before seeds can't be resumed; drop them rather than keep megabytes around.
        defaults.removeObject(forKey: "HashSearch.dp.v2")
        let usesGPU = GPUWalker.isSupported && defaults.bool(forKey: Self.usesGPUKey)
        let seedText = defaults.string(forKey: Self.seedKey) ?? ""
        let saved = defaults.data(forKey: Self.storageKey).flatMap { try? PropertyListDecoder().decode(DistinguishedPointSearch.self, from: $0) }
        let search = saved ?? Self.makeSearch(bits: Self.defaultBits, usesGPU: usesGPU, seedText: seedText)
        self.search = search
        self.usesGPU = usesGPU
        self.seedText = seedText
        seed = search.seed.text
        bits = search.step.bits
        count = search.hashes
        elapsed = search.seconds
        collision = search.collision
    }

    /// GPU searches need longer trails, so the CPU can keep up with the points thousands of walkers report.
    private static func makeSearch(bits: Int, usesGPU: Bool, seedText: String) -> DistinguishedPointSearch {
        let seed = seedText.isEmpty ? Seed.random() : Seed(seedText)
        let dpBits = usesGPU ? GPUWalker.dpBits(bits: bits) : nil
        return DistinguishedPointSearch(bits: bits, seed: seed, dpBits: dpBits)
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
            newSearch()
        }
        isComputing = true
        rateSample = nil
        let generation = bumpGeneration()
        let onGPU = usesGPU
        queue.async { [weak self] in
            self?.runBatch(generation: generation, onGPU: onGPU)
        }
    }

    /// Applies the settings screen. Any change pauses and starts a new search.
    func configure(bits: Int, usesGPU: Bool, seedText: String) {
        let usesGPU = usesGPU && isGPUAvailable
        guard bits != self.bits || usesGPU != self.usesGPU || seedText != self.seedText else { return }
        pause()
        self.bits = bits
        self.usesGPU = usesGPU
        self.seedText = seedText
        defaults.set(usesGPU, forKey: Self.usesGPUKey)
        defaults.set(seedText, forKey: Self.seedKey)
        newSearch()
    }

    func pause() {
        guard isComputing else { return }
        isComputing = false
        hashesPerSecond = 0
        bumpGeneration()
        save()
    }

    /// Starts over with the current settings: the typed seed, or a fresh random one. Only allowed while paused.
    func newSearch() {
        guard !isComputing else { return }
        let search = Self.makeSearch(bits: bits, usesGPU: usesGPU, seedText: seedText)
        seed = search.seed.text
        count = 0
        elapsed = 0
        collision = nil
        bumpGeneration()
        queue.async { [weak self] in
            guard let self else { return }
            self.search = search
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
        if let gpu {
            search.gpuTrails = gpu.trailState
        }
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

        let began = Date()
        let found: Collision?
        if onGPU, let gpu = gpuWalker() {
            let result = gpu.run(seconds: Self.roundSeconds)
            found = search.absorb(result.found, hashes: result.hashes)
        } else {
            found = search.run(seconds: Self.roundSeconds)
        }
        search.seconds += Date().timeIntervalSince(began)
        let count = search.hashes
        let elapsed = search.seconds
        if found != nil {
            persist()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.count = count
            self.elapsed = elapsed
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
        if gpu == nil {
            gpu = GPUWalker(step: search.step, dpBits: search.dpBits, maxTrailLength: search.maxTrailLength,
                            seed: search.gpuSeed, trails: search.gpuTrails)
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
