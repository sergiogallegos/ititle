import XCTest
import ITileCore
@testable import ITilePlatform

final class SheetSummaryTests: XCTestCase {
    func testSheetIsDetectedAlongsideOrdinaryControls() {
        let summary = DirectSheetSummary(total: 3, roles: [.value("other-role"), .value("AXSheet"), .value("other-role")])
        XCTAssertEqual(summary.observedSheets, 1)
        XCTAssertTrue(summary.complete)
    }

    func testFailedReadCannotClaimCompleteAbsence() {
        for failure: ProbeRead<String> in [.unavailable(-25204), .invalidType] {
            let summary = DirectSheetSummary(total: 2, roles: [.value("other-role"), failure])
            XCTAssertEqual(summary.observedSheets, 0)
            XCTAssertFalse(summary.complete)
        }
    }

    func testTruncationPreservesPositiveEvidenceWithoutClaimingCompleteness() {
        let summary = DirectSheetSummary(total: 30, roles: [.value("AXSheet")])
        XCTAssertEqual(summary.observedSheets, 1)
        XCTAssertFalse(summary.complete)
    }
}
