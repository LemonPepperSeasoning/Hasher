//
//  HasherTests.swift
//  HasherTests
//
//  Created by Birth of Venus on 5/09/22.
//

import XCTest
@testable import Hasher

class HasherTests: XCTestCase {

    func testComputeOneStoresHashes() {
        let computer = HashComputer()
        for _ in 0..<10_000 {
            XCTAssertNil(computer.computeOne())
        }
        XCTAssertEqual(computer.counter, 10_000)
        XCTAssertEqual(computer.storedCount, 10_000)
    }

    func testTableIsCappedAndMemoryStaysBounded() {
        let computer = HashComputer()
        let before = memoryFootprint()
        for _ in 0..<(HashComputer.maxStoredHashes + 50_000) {
            _ = computer.computeOne()
        }
        XCTAssertTrue(computer.isTableFull)
        XCTAssertEqual(computer.storedCount, HashComputer.maxStoredHashes)

        let grownMB = Double(Int64(memoryFootprint()) - Int64(before)) / 1_048_576
        print("Table memory: \(grownMB) MB")
        XCTAssertLessThan(grownMB, 300)

        computer.clearStoredHashes()
        XCTAssertEqual(computer.storedCount, 0)
    }

    func testRapidStartPauseRunsOnlyOneLoopAndStops() {
        let search = HashSearch()
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

    func testSearchIsReleased() {
        weak var weakSearch: HashSearch?
        do {
            let search = HashSearch()
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

    private func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

}
