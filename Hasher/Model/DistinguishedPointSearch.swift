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
struct DistinguishedPointSearch: Codable {

    struct Trail: Codable, Equatable {
        var start: Point
        var current: Point
        var length: UInt64
    }

    struct Record: Codable, Equatable {
        let start: Point
        let length: UInt64
    }

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

    init(bits: Int, walkers: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.init(step: HashStep(bits: bits), walkers: walkers)
    }

    init(step: HashStep, walkers: Int, dpBits: Int? = nil) {
        self.step = step
        self.dpBits = dpBits ?? Self.dpBits(bits: step.bits, walkers: walkers)
        maxTrailLength = 20 << UInt64(self.dpBits)
        self.walkers = (0..<max(walkers, 1)).map { _ in
            let start = step.randomPoint()
            return Trail(start: start, current: start, length: 0)
        }
    }

    /// Short trails find a merge soon after it happens; long trails store fewer points.
    /// Aim for trails much shorter than the √N total work split across walkers.
    static func dpBits(bits: Int, walkers: Int) -> Int {
        let walkerBits = Int(ceil(log2(Double(max(walkers, 1)))))
        return min(max(bits / 2 - walkerBits - 4, 0), 28)
    }

    func isDistinguished(_ x: Point) -> Bool {
        dpBits == 0 || x.w0 >> (64 - UInt64(dpBits)) == 0
    }

    /// Runs every walker in parallel for about `seconds`, then checks the new distinguished points.
    mutating func run(seconds: Double) -> Collision? {
        guard collision == nil else { return collision }

        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1e9)
        var found = [[(Point, Record)]](repeating: [], count: walkers.count)
        var counts = [UInt64](repeating: 0, count: walkers.count)
        let search = self
        walkers.withUnsafeMutableBufferPointer { trails in
            found.withUnsafeMutableBufferPointer { found in
                counts.withUnsafeMutableBufferPointer { counts in
                    DispatchQueue.concurrentPerform(iterations: trails.count) { i in
                        counts[i] = search.walk(&trails[i], until: deadline, found: &found[i])
                    }
                }
            }
        }
        return absorb(found.joined(), hashes: counts.reduce(0, +))
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

    /// Steps one trail until the deadline, collecting the distinguished points it reaches.
    private func walk(_ trail: inout Trail, until deadline: UInt64, found: inout [(Point, Record)]) -> UInt64 {
        var count: UInt64 = 0
        repeat {
            for _ in 0..<512 {
                let next = step(trail.current)
                trail.length += 1
                count += 1
                if isDistinguished(next) {
                    found.append((next, Record(start: trail.start, length: trail.length)))
                    restart(&trail)
                } else if trail.length >= maxTrailLength {
                    restart(&trail)
                } else {
                    trail.current = next
                }
            }
        } while DispatchTime.now().uptimeNanoseconds < deadline
        return count
    }

    private func restart(_ trail: inout Trail) {
        let start = step.randomPoint()
        trail = Trail(start: start, current: start, length: 0)
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
