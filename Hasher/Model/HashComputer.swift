//
//  Computer.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import Foundation
import CryptoKit

extension String {

    func hash256() -> String {
        let inputData = Data(utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    subscript(value: CountableClosedRange<Int>) -> Substring {
        self[index(at: value.lowerBound)...index(at: value.upperBound)]
    }

    subscript(value: CountableRange<Int>) -> Substring {
        self[index(at: value.lowerBound)..<index(at: value.upperBound)]
    }

    subscript(value: PartialRangeUpTo<Int>) -> Substring {
        self[..<index(at: value.upperBound)]
    }

    subscript(value: PartialRangeThrough<Int>) -> Substring {
        self[...index(at: value.upperBound)]
    }

    subscript(value: PartialRangeFrom<Int>) -> Substring {
        self[index(at: value.lowerBound)...]
    }

}

private extension String {
    func index(at offset: Int) -> String.Index {
        index(startIndex, offsetBy: offset)
    }
}


struct Collision: Equatable {
    let stringA: String
    let stringB: String
    let hash: String
}


/// Not thread-safe: only use it from one thread or serial queue (see `HashSearch`).
final class HashComputer {

    static let stringLength = 20
    /// Caps the table at ~130 MB so iOS never kills the app for memory.
    /// Once full, new hashes are still checked against the stored ones but not added.
    static let maxStoredHashes = 4_000_000

    private static let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
    private static let golden: UInt64 = 0x9E3779B97F4A7C15

    private(set) var counter: UInt64 = 0
    // Inputs are derived from (seed, index), so only the index needs storing, not the string.
    private let seed = UInt64.random(in: .min ... .max)
    // First 8 bytes of the digest -> index of the input that produced it.
    private var seen: [UInt64: UInt64] = [:]

    var storedCount: Int { seen.count }
    var isTableFull: Bool { seen.count >= Self.maxStoredHashes }

    func computeOne() -> Collision? {
        if seen.isEmpty {
            // Reserve up front so the table never rehashes (which briefly doubles memory).
            seen.reserveCapacity(Self.maxStoredHashes)
        }

        let index = counter
        counter += 1

        let input = inputBytes(for: index)
        let digest = SHA256.hash(data: input)
        let key = digest.prefix(8).reduce(0) { $0 << 8 | UInt64($1) }

        if let otherIndex = seen[key] {
            let other = inputBytes(for: otherIndex)
            // A prefix match is only a candidate; confirm the full digest and that the inputs differ.
            if other != input && SHA256.hash(data: other) == digest {
                print("--- HASH COLLISION FOUND ---")
                return Collision(
                    stringA: String(decoding: other, as: UTF8.self),
                    stringB: String(decoding: input, as: UTF8.self),
                    hash: digest.map { String(format: "%02x", $0) }.joined()
                )
            }
            return nil
        }

        if !isTableFull {
            seen[key] = index
        }
        return nil
    }

    /// Frees the table, e.g. on a memory warning. The counter keeps going.
    func clearStoredHashes() {
        seen = [:]
    }

    /// Deterministic random-looking alphanumeric string for `index` (SplitMix64).
    private func inputBytes(for index: UInt64) -> [UInt8] {
        var state = seed &+ index &* UInt64(Self.stringLength) &* Self.golden
        return (0..<Self.stringLength).map { _ in
            state &+= Self.golden
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            let pick = z.multipliedFullWidth(by: UInt64(Self.characters.count)).high
            return Self.characters[Int(pick)]
        }
    }
}
