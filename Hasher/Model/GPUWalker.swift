//
//  GPUWalker.swift
//  Hasher
//

import Foundation
import Metal

/// Runs thousands of distinguished-point walkers on the GPU (Walk.metal), one per thread.
///
/// The GPU only walks and reports distinguished points; `DistinguishedPointSearch` stores them
/// and re-walks merging trails on the CPU. Trails in flight live in GPU memory between dispatches;
/// `trailState` copies them out so a saved search resumes exactly where it stopped.
final class GPUWalker {

    static let threadCount = 32_768
    private static let threadgroupSize = 256
    private static let recordCapacity = 1 << 16
    private static let trailWords = 20
    private static let recordWords = 18
    /// Steps per dispatch. Fixed rather than tuned to the GPU's speed, so where dispatches start and end, and with
    /// them the order points reach the search, depends only on the seed. That is 16.8 million hashes, about 40 ms
    /// on a Mac GPU, and with at least 10 dp bits about 16,000 points on average, well inside `recordCapacity`.
    private static let stepsPerDispatch: UInt32 = 512

    static var isSupported: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Trails must be long enough that reporting points doesn't swamp the CPU.
    static func dpBits(bits: Int) -> Int {
        min(max(DistinguishedPointSearch.dpBits(bits: bits, walkers: threadCount), 10), 28)
    }

    let step: HashStep
    let dpBits: Int

    private let queue: MTLCommandQueue
    private let walkPipeline: MTLComputePipelineState
    private let hashPipeline: MTLComputePipelineState
    private let params: MTLBuffer
    private let trails: MTLBuffer
    private let records: MTLBuffer
    private let recordCount: MTLBuffer

    /// Each thread's generator is drawn from `seed`. `trails`, from an earlier `trailState`, resumes those walks instead.
    init?(step: HashStep, dpBits: Int, maxTrailLength: UInt64, seed: UInt64 = .random(in: .min ... .max), trails saved: Data? = nil) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = Self.library(device: device),
              let walk = library.makeFunction(name: "walk"),
              let hash = library.makeFunction(name: "hashPoints"),
              let walkPipeline = try? device.makeComputePipelineState(function: walk),
              let hashPipeline = try? device.makeComputePipelineState(function: hash),
              let queue = device.makeCommandQueue(),
              let params = device.makeBuffer(length: 10 * 4, options: .storageModeShared),
              let trails = device.makeBuffer(length: Self.threadCount * Self.trailWords * 4, options: .storageModeShared),
              let records = device.makeBuffer(length: Self.recordCapacity * Self.recordWords * 4, options: .storageModeShared),
              let recordCount = device.makeBuffer(length: 4, options: .storageModeShared)
        else { return nil }

        self.step = step
        self.dpBits = dpBits
        self.queue = queue
        self.walkPipeline = walkPipeline
        self.hashPipeline = hashPipeline
        self.params = params
        self.trails = trails
        self.records = records
        self.recordCount = recordCount

        let p = params.contents().bindMemory(to: UInt32.self, capacity: 10)
        p[0] = UInt32(step.salt0 >> 32)
        p[1] = UInt32(truncatingIfNeeded: step.salt0)
        p[2] = UInt32(step.salt1 >> 32)
        p[3] = UInt32(truncatingIfNeeded: step.salt1)
        p[4] = UInt32(step.bits)
        p[5] = UInt32(dpBits)
        p[7] = UInt32(Self.recordCapacity)
        p[8] = UInt32(truncatingIfNeeded: maxTrailLength)
        p[9] = UInt32(maxTrailLength >> 32)

        if let saved, saved.count == trails.length {
            saved.withUnsafeBytes { trails.contents().copyMemory(from: $0.baseAddress!, byteCount: saved.count) }
            return
        }
        let t = trails.contents().bindMemory(to: UInt32.self, capacity: Self.threadCount * Self.trailWords)
        var seeds = SplitMix64(state: seed)
        for i in 0..<Self.threadCount {
            let trail = t + i * Self.trailWords
            var rng = SplitMix64(state: seeds.next())
            let start = step.randomPoint(using: &rng)
            Self.write(start, to: trail)
            Self.write(start, to: trail + 8)
            trail[16] = 0
            trail[17] = 0
            trail[18] = UInt32(truncatingIfNeeded: rng.state)
            trail[19] = UInt32(rng.state >> 32)
        }
    }

    /// Every thread's trail and generator, as they stand between dispatches.
    var trailState: Data {
        Data(bytes: trails.contents(), count: trails.length)
    }

    /// Walk.metal ships as a resource and is compiled on first use, so building the app
    /// doesn't need Xcode's separately downloaded Metal toolchain.
    private static func library(device: MTLDevice) -> MTLLibrary? {
        guard let url = Bundle(for: GPUWalker.self).url(forResource: "Walk", withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return try? device.makeLibrary(source: source, options: nil)
    }

    /// Dispatches walks for about `seconds` and returns the distinguished points reached.
    func run(seconds: Double) -> (found: [(Point, DistinguishedPointSearch.Record)], hashes: UInt64) {
        var found: [(Point, DistinguishedPointSearch.Record)] = []
        var hashes: UInt64 = 0
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let steps = Self.stepsPerDispatch
            recordCount.contents().storeBytes(of: 0, as: UInt32.self)
            params.contents().storeBytes(of: steps, toByteOffset: 6 * 4, as: UInt32.self)

            guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else { break }
            encoder.setComputePipelineState(walkPipeline)
            encoder.setBuffer(trails, offset: 0, index: 0)
            encoder.setBuffer(records, offset: 0, index: 1)
            encoder.setBuffer(recordCount, offset: 0, index: 2)
            encoder.setBuffer(params, offset: 0, index: 3)
            encoder.dispatchThreadgroups(MTLSize(width: Self.threadCount / Self.threadgroupSize, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: Self.threadgroupSize, height: 1, depth: 1))
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            guard commands.status == .completed else { break }

            hashes += UInt64(Self.threadCount) * UInt64(steps)
            let reported = Int(recordCount.contents().load(as: UInt32.self))
            let r = records.contents().bindMemory(to: UInt32.self, capacity: Self.recordCapacity * Self.recordWords)
            // Points past the capacity are lost work, not wrong results: their threads have already restarted.
            var batch = (0..<min(reported, Self.recordCapacity)).map { i -> (Point, DistinguishedPointSearch.Record) in
                let record = r + i * Self.recordWords
                let length = UInt64(record[16]) | UInt64(record[17]) << 32
                return (Self.read(record), .init(start: Self.read(record + 8), length: length))
            }
            // Threads report in whatever order they get there; sorting makes the search repeatable.
            batch.sort { ($0.0, $0.1.start) < ($1.0, $1.1.start) }
            found += batch
        } while Date() < deadline
        return (found, hashes)
    }

    /// Applies the GPU step function to each point. Used to check it matches `HashStep` exactly.
    func hash(_ points: [Point]) -> [Point] {
        let device = queue.device
        let words = points.flatMap { p in p.words.flatMap { [UInt32($0 >> 32), UInt32(truncatingIfNeeded: $0)] } }
        guard !points.isEmpty,
              let input = device.makeBuffer(bytes: words, length: words.count * 4, options: .storageModeShared),
              let output = device.makeBuffer(length: words.count * 4, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder()
        else { return [] }
        encoder.setComputePipelineState(hashPipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        encoder.setBuffer(params, offset: 0, index: 2)
        encoder.dispatchThreadgroups(MTLSize(width: points.count, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let out = output.contents().bindMemory(to: UInt32.self, capacity: words.count)
        return (0..<points.count).map { Self.read(out + $0 * 8) }
    }

    private static func read(_ words: UnsafeMutablePointer<UInt32>) -> Point {
        func word(_ i: Int) -> UInt64 { UInt64(words[2 * i]) << 32 | UInt64(words[2 * i + 1]) }
        return Point(w0: word(0), w1: word(1), w2: word(2), w3: word(3))
    }

    private static func write(_ point: Point, to words: UnsafeMutablePointer<UInt32>) {
        for (i, word) in point.words.enumerated() {
            words[2 * i] = UInt32(word >> 32)
            words[2 * i + 1] = UInt32(truncatingIfNeeded: word)
        }
    }
}
