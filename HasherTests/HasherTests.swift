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

    func testRhoFindsRealCollisions() {
        for bits in [24, 32] {
            var search = RhoSearch(bits: bits)
            var collision: Collision?
            while collision == nil {
                collision = search.run(maxHashes: 100_000)
            }
            let found = collision!
            XCTAssertNotEqual(found.inputA, found.inputB)
            XCTAssertNotEqual(found.digestA, found.digestB, "full digests should still differ")
            XCTAssertEqual(found.digestA.prefix(bits / 4), found.digestB.prefix(bits / 4))
        }
    }

    func testRhoResumesFromSavedState() throws {
        let step = HashStep(bits: 32, salt0: 1, salt1: 2)
        let start = Point(w0: 0x1234567800000000)

        var straight = RhoSearch(step: step, start: start)
        var expected: Collision?
        while expected == nil {
            expected = straight.run(maxHashes: 1_000_000)
        }

        // Same walk, but saved and restored every 777 hashes.
        var resumed = RhoSearch(step: step, start: start)
        var found: Collision?
        while found == nil {
            found = resumed.run(maxHashes: 777)
            let data = try JSONEncoder().encode(resumed)
            resumed = try JSONDecoder().decode(RhoSearch.self, from: data)
        }
        XCTAssertEqual(found, expected)
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
