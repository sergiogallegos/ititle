import XCTest
@testable import ITileCore

final class LatencySummaryTests: XCTestCase {
    func testTailSpikeIsNotHiddenByMedian() {
        let summary = LatencySummary(Array(repeating: 0.01, count: 18) + [0.8, 1.0])!
        XCTAssertEqual(summary.count, 20)
        XCTAssertEqual(summary.median, 0.01)
        XCTAssertEqual(summary.p95, 0.8)
        XCTAssertEqual(summary.maximum, 1)
    }

    func testInvalidSamplesCannotBecomePerformanceEvidence() {
        for values: [Double] in [[], [0, .nan], [.infinity], [-1]] {
            XCTAssertNil(LatencySummary(values))
        }
    }

    func testTwoSamplesAndLargeFiniteMedian() {
        XCTAssertEqual(LatencySummary([0.4, 0.2])!.median, 0.3, accuracy: 1e-12)
        XCTAssertEqual(LatencySummary([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude])!.median,
                       Double.greatestFiniteMagnitude)
    }
}
