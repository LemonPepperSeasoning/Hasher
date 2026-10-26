//
//  Computer.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import Foundation
import CryptoKit

/// A value in the search space: the first `bits` bits of a 256-bit number (big-endian words), the rest zero.
struct Point: Hashable, Codable, Comparable {
    var w0: UInt64 = 0
    var w1: UInt64 = 0
    var w2: UInt64 = 0
    var w3: UInt64 = 0

    var words: [UInt64] { [w0, w1, w2, w3] }

    func masked(toBits bits: Int) -> Point {
        func mask(_ word: Int) -> UInt64 {
            let kept = min(max(bits - 64 * word, 0), 64)
            return kept == 0 ? 0 : ~0 << (64 - kept)
        }
        return Point(w0: w0 & mask(0), w1: w1 & mask(1), w2: w2 & mask(2), w3: w3 & mask(3))
    }

    func hex(bits: Int = 256) -> String {
        String(words.map { String(format: "%016llx", $0) }.joined().prefix((bits + 3) / 4))
    }

    static func < (a: Point, b: Point) -> Bool {
        (a.w0, a.w1, a.w2, a.w3) < (b.w0, b.w1, b.w2, b.w3)
    }
}

/// SplitMix64, the same generator Walk.metal uses: fast, and fully determined by its state.
struct SplitMix64: RandomNumberGenerator, Codable, Equatable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// What makes a search repeatable: the salt and every walker's starting points are derived from it.
struct Seed: Codable, Equatable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    /// Word `i` (0...3) of SHA-256(text).
    func word(_ i: Int) -> UInt64 {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)))
        return bytes[8 * i ..< 8 * i + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }

    private static let adjectives = ["amber", "brisk", "calm", "coral", "dusty", "eager", "faint", "gentle",
                                     "hollow", "ivory", "jolly", "lunar", "misty", "noble", "quiet", "rapid",
                                     "silver", "steady", "tidal", "velvet"]
    private static let nouns = ["badger", "comet", "delta", "ember", "falcon", "finch", "harbor", "heron",
                                "koi", "lynx", "maple", "meadow", "moth", "orbit", "otter", "pebble",
                                "quartz", "raven", "willow", "zephyr"]

    /// An easy-to-read seed like "silver-otter-4821".
    static func random() -> Seed {
        Seed("\(adjectives.randomElement()!)-\(nouns.randomElement()!)-\(Int.random(in: 1000...9999))")
    }
}

/// The function the search walks: x -> first `bits` bits of SHA-256(salt || x).
///
/// Comparing only the first `bits` bits is what makes collisions findable at small sizes;
/// at 256 bits this is plain SHA-256 on a 48-byte message.
struct HashStep: Codable, Equatable {
    let bits: Int
    let salt0: UInt64
    let salt1: UInt64

    init(bits: Int, salt0: UInt64 = .random(in: .min ... .max), salt1: UInt64 = .random(in: .min ... .max)) {
        self.bits = bits
        self.salt0 = salt0
        self.salt1 = salt1
    }

    init(bits: Int, seed: Seed) {
        self.init(bits: bits, salt0: seed.word(0), salt1: seed.word(1))
    }

    func callAsFunction(_ x: Point) -> Point {
        digest(x).masked(toBits: bits)
    }

    /// The full 256-bit SHA-256 of the input, without truncation.
    func digest(_ x: Point) -> Point {
        var message = (salt0.bigEndian, salt1.bigEndian, x.w0.bigEndian, x.w1.bigEndian, x.w2.bigEndian, x.w3.bigEndian)
        let digest = withUnsafeBytes(of: &message) { SHA256.hash(data: $0) }
        var out = Point()
        digest.withUnsafeBytes { bytes in
            withUnsafeMutableBytes(of: &out) { $0.copyMemory(from: bytes) }
        }
        return Point(w0: UInt64(bigEndian: out.w0), w1: UInt64(bigEndian: out.w1),
                     w2: UInt64(bigEndian: out.w2), w3: UInt64(bigEndian: out.w3))
    }

    func randomPoint() -> Point {
        var rng = SystemRandomNumberGenerator()
        return randomPoint(using: &rng)
    }

    /// Draws words in the same order as Walk.metal's `restartTrail`.
    func randomPoint<R: RandomNumberGenerator>(using rng: inout R) -> Point {
        Point(w0: rng.next(), w1: rng.next(), w2: rng.next(), w3: rng.next()).masked(toBits: bits)
    }

    var saltHex: String { String(format: "%016llx%016llx", salt0, salt1) }
}

struct Collision: Codable, Equatable {
    let bits: Int
    let salt: String
    let inputA: String
    let inputB: String
    /// Full SHA-256 of each input; the first `bits` bits are equal.
    let digestA: String
    let digestB: String

    init(step: HashStep, a: Point, b: Point) {
        bits = step.bits
        salt = step.saltHex
        inputA = a.hex(bits: step.bits)
        inputB = b.hex(bits: step.bits)
        digestA = step.digest(a).hex()
        digestB = step.digest(b).hex()
    }
}
