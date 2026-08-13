import XCTest
@testable import NetScan

final class ResolverGateTests: XCTestCase {
    func testLimitsConcurrentHolders() async {
        let gate = ResolverGate(limit: 2)
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await gate.acquire()
                    let current = await counter.increment()
                    XCTAssertLessThanOrEqual(current, 2)
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    await counter.decrement()
                    await gate.release()
                }
            }
        }

        let peak = await counter.peak
        XCTAssertGreaterThan(peak, 0)
        XCTAssertLessThanOrEqual(peak, 2)
    }

    func testAllTasksEventuallyRun() async {
        let gate = ResolverGate(limit: 1)
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await gate.acquire()
                    await counter.recordCompletion()
                    await gate.release()
                }
            }
        }

        let completions = await counter.completions
        XCTAssertEqual(completions, 20)
    }
}

private actor ConcurrencyCounter {
    private var current = 0
    private(set) var peak = 0
    private(set) var completions = 0

    func increment() -> Int {
        current += 1
        peak = max(peak, current)
        return current
    }

    func decrement() {
        current -= 1
    }

    func recordCompletion() {
        completions += 1
    }
}
