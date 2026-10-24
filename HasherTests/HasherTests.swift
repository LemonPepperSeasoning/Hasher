//
//  HasherTests.swift
//  HasherTests
//
//  Created by Birth of Venus on 5/09/22.
//

import XCTest
import CryptoKit
@testable import Hasher

class HasherTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "HasherTests")
        defaults.removePersistentDomain(forName: "HasherTests")
    }

    func testStepMatchesCryptoKitAndIsTruncated() {
        let step = HashStep(bits: 40, salt0: 0x0123456789abcdef, salt1: 0xfedcba9876543210)
        let x = Point(w0: 0xaabbccdd00000000, w1: 0, w2: 0, w3: 0)

        var message = Data()
        for word in [step.salt0, step.salt1, x.w0, x.w1, x.w2, x.w3] {
            withUnsafeBytes(of: word.bigEndian) { message.append(contentsOf: $0) }
        }
        let expected = SHA256.hash(data: message).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(step.digest(x).hex(), expected)
        XCTAssertEqual(step(x).hex(bits: 40), String(expected.prefix(10)))
        XCTAssertEqual(step(x), step(x).masked(toBits: 40), "bits past 40 must be zero")
    }

    func testDistinguishedPointsFindRealCollisions() {
        for bits in [24, 32, 40] {
            var search = DistinguishedPointSearch(bits: bits, walkers: 4)
            var collision: Collision?
            while collision == nil {
                collision = search.run(seconds: 0.05)
            }
            let found = collision!
            XCTAssertNotEqual(found.inputA, found.inputB)
            XCTAssertNotEqual(found.digestA, found.digestB, "full digests should still differ")
            XCTAssertEqual(found.digestA.prefix(bits / 4), found.digestB.prefix(bits / 4))
        }
    }

    func testMergeFindsTheJunctionAndRejectsSharedPaths() {
        var search = DistinguishedPointSearch(step: HashStep(bits: 16, salt0: 7, salt1: 8), walkers: 1)
        let step = search.step

        // Two trails on the same path, one 5 steps behind the other: no collision.
        let start = Point(w0: 0x1234 << 48)
        var ahead = start
        for _ in 0..<5 { ahead = step(ahead) }
        XCTAssertNil(search.merge(.init(start: start, length: 50), .init(start: ahead, length: 45)))

        // Two different inputs with the same 16-bit hash are trails that merge after one step.
        var seen: [Point: Point] = [:]
        var pair: (Point, Point)?
        for i in UInt64(0)..<65_536 where pair == nil {
            let x = Point(w0: i << 48)
            if let other = seen[step(x)] { pair = (other, x) }
            seen[step(x)] = x
        }
        let (a, b) = pair!
        let merged = search.merge(.init(start: a, length: 1), .init(start: b, length: 1))
        XCTAssertEqual(merged?.0, a)
        XCTAssertEqual(merged?.1, b)
    }

    func testDistinguishedPointSearchResumesFromSavedState() throws {
        var search = DistinguishedPointSearch(bits: 36, walkers: 4)
        var collision: Collision?
        var rounds = 0
        while collision == nil {
            collision = search.run(seconds: 0.02)
            let data = try PropertyListEncoder().encode(search)
            search = try PropertyListDecoder().decode(DistinguishedPointSearch.self, from: data)
            rounds += 1
        }
        XCTAssertGreaterThan(rounds, 1)
        XCTAssertEqual(collision!.digestA.prefix(9), collision!.digestB.prefix(9))
        XCTAssertEqual(search.collision, collision)
    }

    func testWalkersScaleAcrossCores() throws {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        try XCTSkipIf(cores < 2)
        func hashesPerSecond(walkers: Int) -> Double {
            var search = DistinguishedPointSearch(bits: 256, walkers: walkers)
            _ = search.run(seconds: 1)
            return Double(search.hashes)
        }
        let one = hashesPerSecond(walkers: 1), all = hashesPerSecond(walkers: cores)
        print("1 walker: \(Int(one)) hashes/s, \(cores) walkers: \(Int(all)) hashes/s (\(String(format: "%.1f", all / one))x)")
        XCTAssertGreaterThan(all, one * 1.5)
    }

    func testGPUStepMatchesCPUExactly() throws {
        try XCTSkipUnless(GPUWalker.isSupported, "no Metal device")
        for bits in [24, 40, 64, 100, 256] {
            let step = HashStep(bits: bits)
            let gpu = try XCTUnwrap(GPUWalker(step: step, dpBits: 10, maxTrailLength: 1_000))
            let inputs = (0..<256).map { _ in step.randomPoint() }
            XCTAssertEqual(gpu.hash(inputs), inputs.map { step($0) }, "\(bits) bits")
        }
    }

    func testGPUWalkersReportValidTrailsAndFindCollision() throws {
        try XCTSkipUnless(GPUWalker.isSupported, "no Metal device")
        let bits = 48
        var search = DistinguishedPointSearch(step: HashStep(bits: bits), walkers: 1, dpBits: GPUWalker.dpBits(bits: bits))
        let gpu = try XCTUnwrap(GPUWalker(step: search.step, dpBits: search.dpBits, maxTrailLength: search.maxTrailLength))

        var checked = 0
        var collision: Collision?
        let deadline = Date().addingTimeInterval(120)
        while collision == nil && Date() < deadline {
            let result = gpu.run(seconds: 0.1)
            // Re-walk a sample of reported trails on the CPU: each must end at its point, at the first distinguished step.
            for (point, record) in result.found.prefix(max(0, 20 - checked)) {
                var x = record.start
                for i in 1...record.length {
                    x = search.step(x)
                    XCTAssertEqual(search.isDistinguished(x), i == record.length)
                }
                XCTAssertEqual(x, point)
                checked += 1
            }
            collision = search.absorb(result.found, hashes: result.hashes)
        }
        let found = try XCTUnwrap(collision, "no collision within 2 minutes")
        XCTAssertGreaterThan(checked, 0)
        XCTAssertNotEqual(found.inputA, found.inputB)
        XCTAssertEqual(found.digestA.prefix(bits / 4), found.digestB.prefix(bits / 4))
        XCTAssertNotEqual(found.digestA, found.digestB)
        print("GPU found a \(bits)-bit collision after \(search.hashes) hashes")
    }

    func testGPUThroughput() throws {
        try XCTSkipUnless(GPUWalker.isSupported, "no Metal device")
        let step = HashStep(bits: 256)
        let gpu = try XCTUnwrap(GPUWalker(step: step, dpBits: 28, maxTrailLength: .max))
        _ = gpu.run(seconds: 0.3) // warm up and settle the dispatch size
        let gpuRate = Double(gpu.run(seconds: 1).hashes)
        var cpu = DistinguishedPointSearch(step: step, walkers: ProcessInfo.processInfo.activeProcessorCount)
        _ = cpu.run(seconds: 1)
        print("GPU: \(Int(gpuRate)) hashes/s, CPU: \(cpu.hashes) hashes/s (\(String(format: "%.1f", gpuRate / Double(cpu.hashes)))x)")
        XCTAssertGreaterThan(gpuRate, 0)
    }

    func testRapidStartPauseRunsOnlyOneLoopAndStops() {
        let search = HashSearch(defaults: defaults)
        for _ in 0..<500 {
            search.toggle()
        }
        search.start()
        waitForMainQueue(seconds: 1)
        XCTAssertTrue(search.isComputing)
        XCTAssertGreaterThan(search.count, 0)

        search.pause()
        waitForMainQueue(seconds: 0.5)
        let countAfterPause = search.count
        waitForMainQueue(seconds: 0.5)
        XCTAssertFalse(search.isComputing)
        XCTAssertEqual(search.count, countAfterPause, "a loop kept running after pause")
    }

    func testSearchFindsCollisionAndRestoresIt() {
        let search = HashSearch(defaults: defaults)
        search.newSearch(bits: 32)
        search.start()
        let deadline = Date().addingTimeInterval(60)
        while search.collision == nil && Date() < deadline {
            waitForMainQueue(seconds: 0.2)
        }
        XCTAssertNotNil(search.collision)
        XCTAssertFalse(search.isComputing)
        waitForMainQueue(seconds: 0.2)

        let relaunched = HashSearch(defaults: defaults)
        XCTAssertEqual(relaunched.bits, 32)
        XCTAssertEqual(relaunched.collision, search.collision)
    }

    func testSearchIsReleased() {
        weak var weakSearch: HashSearch?
        do {
            let search = HashSearch(defaults: defaults)
            weakSearch = search
            search.start()
            waitForMainQueue(seconds: 0.2)
            search.pause()
        }
        waitForMainQueue(seconds: 0.5)
        XCTAssertNil(weakSearch, "HashSearch leaked")
    }

    private func waitForMainQueue(seconds: TimeInterval) {
        let done = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

}
