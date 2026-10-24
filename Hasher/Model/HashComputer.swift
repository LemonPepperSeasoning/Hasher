//
//  Computer.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import Foundation
import CryptoKit

/// A value in the search space: the first `bits` bits of a 256-bit number (big-endian words), the rest zero.
struct Point: Hashable, Codable {
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
        Point(w0: .random(in: .min ... .max), w1: .random(in: .min ... .max),
              w2: .random(in: .min ... .max), w3: .random(in: .min ... .max)).masked(toBits: bits)
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
