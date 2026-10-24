//
//  RhoSearch.swift
//  Hasher
//

import Foundation

/// Pollard's rho with Brent's cycle detection, written as a resumable state machine.
///
/// Walking x -> H(x) must eventually loop. The node where the tail joins the loop has two
/// predecessors (one on the tail, one on the loop) that hash to the same value: a collision.
/// The whole search state is a handful of points, so it can be saved and resumed at any time.
struct RhoSearch: Codable {

    enum Phase: String, Codable {
        /// Brent: the hare walks, the tortoise teleports to it at powers of two, until they meet. Gives λ.
        case findCycle
        /// Put the hare λ steps ahead of x0.
        case advanceHare
        /// Step both together; the step where they first agree is the junction.
        case findJunction
    }

    let step: HashStep
    private(set) var hashes: UInt64 = 0
    /// Walks abandoned because the random start was already on the loop (no tail, no collision).
    private(set) var restarts = 0
    private(set) var phase = Phase.findCycle
    private(set) var cycleLength: UInt64?
    private(set) var collision: Collision?

    private var x0 = Point()
    private var tortoise = Point()
    private var hare = Point()
    private var power: UInt64 = 1
    private var lambda: UInt64 = 1
    private var remaining: UInt64 = 0

    init(bits: Int) {
        self.init(step: HashStep(bits: bits))
    }

    init(step: HashStep, start: Point? = nil) {
        self.step = step
        begin(at: start ?? step.randomPoint())
    }

    /// Runs up to roughly `maxHashes` hash evaluations. Returns the collision once found.
    mutating func run(maxHashes: Int) -> Collision? {
        var budget = maxHashes
        while budget > 0, collision == nil {
            switch phase {
            case .findCycle:
                if tortoise == hare {
                    cycleLength = lambda
                    tortoise = x0
                    hare = x0
                    remaining = lambda
                    phase = .advanceHare
                    continue
                }
                if power == lambda {
                    tortoise = hare
                    power *= 2
                    lambda = 0
                }
                hare = f(hare)
                lambda += 1
                budget -= 1

            case .advanceHare:
                if remaining == 0 {
                    phase = .findJunction
                    continue
                }
                hare = f(hare)
                remaining -= 1
                budget -= 1

            case .findJunction:
                if tortoise == hare {
                    // x0 was already on the loop, so there is no tail to collide with.
                    restarts += 1
                    begin(at: step.randomPoint())
                    continue
                }
                let nextTortoise = f(tortoise)
                let nextHare = f(hare)
                budget -= 2
                if nextTortoise == nextHare {
                    collision = Collision(step: step, a: tortoise, b: hare)
                } else {
                    tortoise = nextTortoise
                    hare = nextHare
                }
            }
        }
        return collision
    }

    private mutating func begin(at start: Point) {
        x0 = start
        tortoise = start
        hare = f(start)
        power = 1
        lambda = 1
        cycleLength = nil
        phase = .findCycle
    }

    private mutating func f(_ x: Point) -> Point {
        hashes += 1
        return step(x)
    }
}
