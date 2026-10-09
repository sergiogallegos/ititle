import Foundation
import ITileFixtureDiagnostics
import XCTest

final class TimingTests: XCTestCase {
  private func record(index: Int = 1) -> FixtureTimingRecord {
    var value = FixtureTimingRecord(index: index, cohort: .ordinary, requestedDelay: 0, run: UUID())
    value.outcome = .completed
    for (point, time): (FixtureTimingPoint, Double) in [
      (.beforeSubmission, 1), (.beforeWrite, 3), (.beforeStart, 2), (.beforeEnd, 4),
      (.beforeReceipt, 5), (.beforeParse, 6), (.admission, 7), (.entry, 10), (.exit, 12),
      (.publication, 13), (.receipt, 17), (.afterSubmission, 18), (.afterWrite, 20),
      (.afterStart, 19), (.afterEnd, 21), (.afterReceipt, 22), (.afterParse, 23),
      (.inputsReady, 24), (.assessmentEntry, 29), (.assessmentExit, 30),
    ] { value.mark(point, at: time) }
    return value
  }

  func testAcquisitionCanPrecedeWriteCompletionAndMetricsAreIndependent() {
    let value = record()
    XCTAssertTrue(value.valid)
    XCTAssertEqual(value.metrics["dispatchWait"], 3)
    XCTAssertEqual(value.metrics["inspection"], 2)
    XCTAssertEqual(value.metrics["replyWait"], 4)
    XCTAssertEqual(value.metrics["assessmentWait"], 5)
    XCTAssertEqual(value.metrics["evidenceAge"], 27)
    XCTAssertEqual(value.metrics["pairLatency"], 29)
  }

  func testPartialFailureRetainsMissingEndpointsAndRejectsNonfiniteOrRegressingTimes() {
    var value = FixtureTimingRecord(index: 1, cohort: .ordinary, requestedDelay: 0, run: UUID())
    value.outcome = .timedOut
    value.mark(.admission, at: 5)
    XCTAssertTrue(value.valid)
    XCTAssertTrue(value.metrics.isEmpty)
    value.mark(.exit, at: 4)
    XCTAssertFalse(value.valid)
    XCTAssertTrue(value.metrics.isEmpty)
    for bad in [Double.nan, .infinity, -1] {
      var value = record()
      value.mark(.assessmentEntry, at: bad)
      XCTAssertFalse(value.valid)
    }
    var partial = FixtureTimingRecord(index: 1, cohort: .ordinary, requestedDelay: 0, run: UUID())
    partial.mark(.beforeStart, at: 5)
    partial.mark(.assessmentEntry, at: 4)
    XCTAssertFalse(partial.valid)
    var early = record()
    early.mark(.inputsReady, at: 22)
    XCTAssertFalse(early.valid)
  }

  func testTimeoutRetainsPhysicalSlotUntilExactDrainAndCannotResumeCollection() throws {
    var collector = FixtureTimingCollector()
    XCTAssertEqual(try collector.begin(.ordinary), 1)
    var value = record()
    value.outcome = .timedOut
    try collector.finish(value, readerDrained: false)
    XCTAssertEqual(collector.occupied, 1)
    XCTAssertThrowsError(try collector.drained(index: 2))
    XCTAssertEqual(collector.occupied, 1)
    XCTAssertThrowsError(try collector.begin(.dispatch))
    try collector.drained(index: 1)
    XCTAssertNil(collector.occupied)
    XCTAssertThrowsError(try collector.begin(.dispatch))
  }

  func testMatchingTerminalAndMalformedTimingStop() throws {
    var collector = FixtureTimingCollector()
    _ = try collector.begin(.ordinary)
    XCTAssertThrowsError(try collector.finish(record(index: 2), readerDrained: true))
    XCTAssertEqual(collector.occupied, 1)
    var value = record()
    value.mark(.entry, at: 0)
    try collector.finish(value, readerDrained: true)
    XCTAssertTrue(collector.stopped)
    XCTAssertEqual(collector.records.last?.outcome, .malformedTiming)
  }

  func testClockRegressionBetweenAttemptsStopsCollection() throws {
    var collector = FixtureTimingCollector()
    _ = try collector.begin(.ordinary)
    try collector.finish(record(), readerDrained: true)
    _ = try collector.begin(.ordinary)
    try collector.finish(record(index: 2), readerDrained: true)
    XCTAssertTrue(collector.stopped)
    XCTAssertEqual(collector.records.last?.outcome, .malformedTiming)
    XCTAssertTrue(collector.records.last!.metrics.isEmpty)
  }

  func testAttemptAndCohortCaps() throws {
    for collector in [
      FixtureTimingCollector(attemptLimit: 1), FixtureTimingCollector(cohortLimit: 1),
    ] {
      var collector = collector
      _ = try collector.begin(.ordinary)
      try collector.finish(record(), readerDrained: true)
      XCTAssertThrowsError(try collector.begin(.ordinary))
    }
  }

  func testOutputAndEventCapsLeaveReservedIncompleteTerminal() throws {
    var collector = FixtureTimingCollector(byteLimit: 1024)
    XCTAssertThrowsError(try collector.append(String(repeating: "x", count: 1024)))
    collector.close(orderly: true, passed: true)
    XCTAssertLessThanOrEqual(collector.bytes.count, 1024)
    let terminal = try XCTUnwrap(
      JSONSerialization.jsonObject(with: collector.bytes) as? [String: Any])
    XCTAssertEqual(terminal["complete"] as? Bool, false)
    let bytes = collector.bytes
    collector.close(orderly: true, passed: true)
    XCTAssertEqual(collector.bytes, bytes)
    XCTAssertThrowsError(try collector.append("late"))
    var events = FixtureTimingCollector(eventLimit: 1)
    let event = FixtureTimingEvent(code: "pause", time: 1, revocation: 1, pending: 1)
    try events.event(event)
    XCTAssertThrowsError(try events.event(event))
    XCTAssertTrue(events.stopped)
  }

  func testSummaryCountsMissingMetricsAndNearestRankTail() throws {
    var a = record()
    a.outcome = .completed
    var b = FixtureTimingRecord(index: 2, cohort: .ordinary, requestedDelay: 0, run: UUID())
    b.outcome = .failed
    let summary = FixtureTimingSummary(records: [a, b])
    let cohort = try XCTUnwrap(summary.cohorts["ordinary"])
    XCTAssertEqual(cohort.attempts, 2)
    XCTAssertEqual(cohort.outcomes["failed"], 1)
    XCTAssertEqual(cohort.metrics["inspection"]?.count, 1)
    XCTAssertEqual(cohort.metrics["inspection"]?.p95, 2)
    XCTAssertTrue(summary.cohorts["dispatch"]!.metrics.isEmpty)
  }
}
