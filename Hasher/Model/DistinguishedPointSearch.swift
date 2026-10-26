//
//  DistinguishedPointSearch.swift
//  Hasher
//

import Foundation

/// Parallel collision search with distinguished points (van Oorschot & Wiener).
///
/// Each walker steps x -> H(x) from a random start until it lands on a *distinguished point*:
/// a value whose first `dpBits` bits are zero. It records (point, start, length) and starts again.
/// Two walks that ever pass through the same value follow the same path from then on, so they
/// reach the same distinguished point. Re-walking both trails from their starts, lined up by
/// length, finds the step where they merged: the two values just before it collide.
///
/// Walkers only share the dictionary of distinguished points, so they scale across cores.
///
/// Everything random comes from the seed and walkers run in rounds of a fixed number of steps,
/// so the same seed finds the same collision however fast the device is or how often it pauses.
struct DistinguishedPointSearch: Codable {

    struct Trail: Codable, Equatable {
        var start: Point
        var current: Point
        var length: UInt64
        /// Draws this walker's next start.
        var rng: SplitMix64
    }

    struct Record: Codable, Equatable {
        let start: Point
        let length: UInt64
    }

    let seed: Seed
    let step: HashStep
    /// A point is distinguished when its first `dpBits` bits are zero; trails average 2^dpBits steps.
    let dpBits: Int
    /// Trails this long are abandoned: they are probably stuck in a loop with no distinguished point.
    let maxTrailLength: UInt64
    private(set) var walkers: [Trail]
    private(set) var points: [Point: Record] = [:]
    private(set) var hashes: UInt64 = 0
    /// Pairs of trails that reached the same point without a collision (one start lay on the other trail).
    private(set) var falseAlarms = 0
    private(set) var collision: Collision?
    /// Time spent searching, kept by `HashSearch` for display.
    var seconds: Double = 0
    /// The GPU walkers' trails at the last save, so a resumed GPU search carries on exactly where it stopped.
    var gpuTrails: Data?

    /// Each walker steps this many times per round. Fixed, so the order points arrive in depends only on the seed.
    private static let stepsPerRound = 4_096
    /// Many more walkers than cores: GCD hands each free core the next walker, so fast cores do more of a
    /// round instead of waiting for slow ones. A fixed count also makes a seed reproducible on any device.
    static let defaultWalkers = 64

    init(bits: Int, seed: Seed = .random(), walkers: Int = defaultWalkers, dpBits: Int? = nil) {
        let step = HashStep(bits: bits, seed: seed)
        self.seed = seed
        self.step = step
        self.dpBits = dpBits ?? Self.dpBits(bits: bits, walkers: walkers)
        maxTrailLength = 20 << UInt64(self.dpBits)
        var seeds = SplitMix64(state: seed.word(2))
        self.walkers = (0..<max(walkers, 1)).map { _ in
            var rng = SplitMix64(state: seeds.next())
            let start = step.randomPoint(using: &rng)
            return Trail(start: start, current: start, length: 0, rng: rng)
        }
    }

    /// Seeds the GPU walkers' generators, kept apart from the CPU walkers'.
    var gpuSeed: UInt64 { seed.word(3) }

    /// Short trails find a merge soon after it happens; long trails store fewer points.
    /// Aim for trails much shorter than the √N total work split across walkers.
    static func dpBits(bits: Int, walkers: Int) -> Int {
        let walkerBits = Int(ceil(log2(Double(max(walkers, 1)))))
        return min(max(bits / 2 - walkerBits - 4, 0), 28)
    }

    func isDistinguished(_ x: Point) -> Bool {
        Self.isDistinguished(x, dpBits: dpBits)
    }

    private static func isDistinguished(_ x: Point, dpBits: Int) -> Bool {
        dpBits == 0 || x.w0 >> (64 - UInt64(dpBits)) == 0
    }

    /// Runs rounds of every walker in parallel for about `seconds`, checking the new distinguished points after each.
    mutating func run(seconds: Double) -> Collision? {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1e9)
        repeat {
            guard collision == nil else { return collision }
            var found = [[(Point, Record)]](repeating: [], count: walkers.count)
            // Walkers see only these values, not the search: reaching into it from every thread retains its
            // arrays and strings, and that reference counting contends between cores.
            let step = step, dpBits = dpBits, maxTrailLength = maxTrailLength
            walkers.withUnsafeMutableBufferPointer { trails in
                found.withUnsafeMutableBufferPointer { found in
                    DispatchQueue.concurrentPerform(iterations: trails.count) { i in
                        // A local copy, so cores don't share cache lines writing neighbouring trails every step.
                        var trail = trails[i]
                        Self.walk(&trail, step: step, dpBits: dpBits, maxTrailLength: maxTrailLength, found: &found[i])
                        trails[i] = trail
                    }
                }
            }
            // Walker order, not finishing order, so the search is the same on every run.
            _ = absorb(found.joined(), hashes: UInt64(walkers.count * Self.stepsPerRound))
        } while DispatchTime.now().uptimeNanoseconds < deadline
        return collision
    }

    /// Adds distinguished points found by any walker (CPU or GPU) and checks them for merges.
    mutating func absorb<S: Sequence>(_ found: S, hashes: UInt64) -> Collision? where S.Element == (Point, Record) {
        self.hashes += hashes
        for (point, record) in found where collision == nil {
            if let pair = store(point, record) {
                collision = Collision(step: step, a: pair.0, b: pair.1)
            }
        }
        return collision
    }

    /// Steps one trail for a round, collecting the distinguished points it reaches.
    private static func walk(_ trail: inout Trail, step: HashStep, dpBits: Int, maxTrailLength: UInt64,
                             found: inout [(Point, Record)]) {
        for _ in 0..<stepsPerRound {
            let next = step(trail.current)
            trail.length += 1
            if isDistinguished(next, dpBits: dpBits) {
                found.append((next, Record(start: trail.start, length: trail.length)))
                restart(&trail, step: step)
            } else if trail.length >= maxTrailLength {
                restart(&trail, step: step)
            } else {
                trail.current = next
            }
        }
    }

    private static func restart(_ trail: inout Trail, step: HashStep) {
        trail.start = step.randomPoint(using: &trail.rng)
        trail.current = trail.start
        trail.length = 0
    }

    /// Stores a distinguished point. If another trail already reached it, finds where they merged.
    private mutating func store(_ point: Point, _ record: Record) -> (Point, Point)? {
        guard let existing = points[point] else {
            points[point] = record
            return nil
        }
        guard existing.start != record.start else { return nil }
        if let pair = merge(existing, record) {
            return pair
        }
        falseAlarms += 1
        // Keep the longer trail: it covers more of the path into this point.
        if record.length > existing.length {
            points[point] = record
        }
        return nil
    }

    /// Re-walks two trails that end at the same point. Returns the colliding pair, or nil if one
    /// trail's start lies on the other trail (they share a path but no two different inputs merge).
    mutating func merge(_ a: Record, _ b: Record) -> (Point, Point)? {
        var x = a.start, y = b.start
        var lengthX = a.length, lengthY = b.length
        while lengthX > lengthY {
            x = step(x)
            lengthX -= 1
            hashes += 1
        }
        while lengthY > lengthX {
            y = step(y)
            lengthY -= 1
            hashes += 1
        }
        if x == y {
            return nil
        }
        // Both are now the same number of steps from the shared point, so they meet by then.
        for _ in 0..<lengthX {
            let nextX = step(x), nextY = step(y)
            hashes += 2
            if nextX == nextY {
                return (x, y)
            }
            x = nextX
            y = nextY
        }
        return nil
    }
}
