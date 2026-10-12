import Foundation
import ITileFixtureDiagnostics
import XCTest

final class TimingReplayTests: XCTestCase {
  private let run = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private var context: FixtureUseContext {
    FixtureUseContext(expected: try! FixtureWindowIdentity(run: run, serial: 1))
  }

  private func snapshot(
    request: UInt64, start: Double, end: Double, changes: [String: String] = [:]
  ) throws -> FixtureSafetySnapshot {
    var fields = Dictionary(uniqueKeysWithValues: FixtureSafetySnapshot.flags.map { ($0, "false") })
    fields.merge([
      "schema": "2", "coverage": "ownedFixtureOnly", "run": run.uuidString,
      "request": String(request), "sequence": String(request), "start": String(start),
      "end": String(end), "original": "1", "number": "1", "tabCount": "1", "sheetCount": "0",
      "scenario": "ordinary", "active": "true", "visible": "true", "frontmost": "true",
      "tabSelected": "notApplicable", "tabBar": "notApplicable", "stateRevision": "2",
      "registryRevision": "2", "liveSerials": "1", "originalLive": "true",
      "lifecycleCoverage": "observedEventsOnly", "uncertainty": "none",
    ]) { _, new in new }
    fields.merge(changes) { _, new in new }
    return try FixtureSafetySnapshot(fields: fields)
  }

  private func record(
    index: Int = 1, cohort: FixtureTimingCohort = .ordinary, delay: Double = 0,
    changes: [String: String] = [:]
  ) throws -> FixtureTimingRecord {
    let base = Double(index) * 40
    let request = UInt64(index * 2 - 1)
    var record = FixtureTimingRecord(index: index, cohort: cohort, requestedDelay: delay, run: run)
    for (point, offset): (FixtureTimingPoint, Double) in [
      (.beforeSubmission, 1), (.beforeWrite, 3), (.beforeStart, 2), (.beforeEnd, 4),
      (.beforeReceipt, 5), (.beforeSelection, 5.5), (.beforeParseEntry, 5.7), (.beforeParse, 6),
      (.hostAdmission, 6.5), (.admission, 7), (.entry, 10), (.exit, 12), (.publication, 13),
      (.receipt, 17), (.afterSubmission, 18), (.afterWrite, 20), (.afterStart, 19), (.afterEnd, 21),
      (.afterReceipt, 22), (.afterSelection, 22.2), (.afterParseEntry, 22.4), (.afterParse, 23),
      (.inputsReady, 24), (.assessmentEntry, 29), (.assessmentExit, 30), (.terminal, 31),
    ] { record.mark(point, at: base + offset) }
    record.request = request
    record.before = try snapshot(request: request, start: base + 2, end: base + 4, changes: changes)
    record.after = try snapshot(
      request: request + 1, start: base + 19, end: base + 21, changes: changes)
    record.admitted = context
    record.final = context
    record.focused = context.expected
    record.axStart = base + 10
    record.axEnd = base + 12
    record.outcome = .completed
    record.assessment = .historicalConsistent
    return record
  }

  private func dataset(
    _ records: [FixtureTimingRecord], events: [FixtureTimingEvent] = [], exclusion: Bool = false
  ) throws
    -> Data
  {
    let manifest = FixtureTimingManifest(
      os: "Test OS", utc: "2026-10-11T00:00:00Z", labHash: String(repeating: "a", count: 64),
      fixtureHash: String(repeating: "b", count: 64), initialContext: context,
      controlledExclusion: exclusion)
    var collector = FixtureTimingCollector()
    try collector.append(manifest)
    for event in events { try collector.event(event) }
    for record in records {
      _ = try collector.begin(record.cohort)
      try collector.finish(record, readerDrained: true)
    }
    try collector.append(FixtureTimingSummary(records: records))
    collector.close(orderly: true, passed: records.count == FixtureTimingBudget.attempts)
    return collector.bytes
  }

  private func mutatePair(_ data: Data, _ mutate: (inout [String: Any]) -> Void) throws -> Data {
    var result = Data()
    for line in data.split(separator: 10) {
      var object = try JSONSerialization.jsonObject(with: Data(line)) as! [String: Any]
      if object["kind"] as? String == "pair" { mutate(&object) }
      result.append(try JSONSerialization.data(withJSONObject: object))
      result.append(10)
    }
    return result
  }

  func testSnapshotAndIdentityRoundTripValidateFixedVocabulary() throws {
    let value = try record()
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(FixtureTimingRecord.self, from: data)
    XCTAssertEqual(decoded.before?.line, value.before?.line)
    XCTAssertEqual(decoded.focused, value.focused)
    XCTAssertTrue(decoded.valid)
    XCTAssertThrowsError(
      try JSONDecoder().decode(FixtureWindowIdentity.self, from: Data("\"arbitrary\"".utf8)))
    let report = try FixtureTimingReplay.review(dataset([value]))
    XCTAssertEqual(report.assessed, 1)
    XCTAssertEqual(report.outcomes["historicalConsistent"], 1)
    XCTAssertFalse(report.complete)
    XCTAssertFalse(report.calibrationSuitable)
  }

  func testParsingSeparatesSelectionWaitAndPureCorrelationCost() throws {
    let value = try record()
    XCTAssertEqual(value.metrics["beforeSelectionWait"]!, 0.5, accuracy: 1e-12)
    XCTAssertEqual(value.metrics["beforeParsing"]!, 0.3, accuracy: 1e-12)
    XCTAssertEqual(value.metrics["beforeReceiptToCompletion"]!, 1, accuracy: 1e-12)
    var malformed = value
    malformed.mark(.afterParseEntry, at: value.time(.afterReceipt)! - 1)
    XCTAssertFalse(malformed.valid)
  }

  func testUnsupportedAndWrongFocusedIdentityReplayWithoutWeakeningGuard() throws {
    var unsupported = try record(changes: ["frontmost": "false"])
    unsupported.assessment = .unsupported
    unsupported.outcome = .rejected
    let report = try FixtureTimingReplay.review(dataset([unsupported]))
    XCTAssertEqual(report.outcomes["unsupported"], 1)
    XCTAssertEqual(report.exclusions["frontmost"], 2)
    var wrong = try record()
    wrong.focused = try FixtureWindowIdentity(run: run, serial: 2)
    wrong.assessment = .wrongWindow
    wrong.outcome = .rejected
    XCTAssertEqual(try FixtureTimingReplay.review(dataset([wrong])).outcomes["wrongWindow"], 1)
    wrong.assessment = .historicalConsistent
    wrong.outcome = .completed
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([wrong])))
  }

  func testPauseResumeOrderedReplayRequiresFreshPairAndMatchingContexts() throws {
    var old = try record()
    var authority = FixtureHostAuthority(context: context)
    authority.update(paused: true)
    let pause = FixtureTimingEvent(
      code: "pause", time: 65, revocation: 1, pending: old.request, context: authority.context)
    authority.update(paused: false)
    let resume = FixtureTimingEvent(
      code: "resume", time: 66, revocation: 2, pending: old.request, context: authority.context)
    old.final = authority.context
    old.assessment = .contextRevoked
    old.outcome = .revoked
    var fresh = try record(index: 2)
    fresh.admitted = authority.context
    fresh.final = authority.context
    let report = try FixtureTimingReplay.review(dataset([old, fresh], events: [pause, resume]))
    XCTAssertEqual(report.outcomes["contextRevoked"], 1)
    XCTAssertEqual(report.outcomes["historicalConsistent"], 1)
    old.assessment = .historicalConsistent
    old.outcome = .completed
    XCTAssertThrowsError(
      try FixtureTimingReplay.review(dataset([old, fresh], events: [pause, resume])))
    let wrong = FixtureTimingEvent(
      code: "pause", time: 65, revocation: 1, pending: 999, context: pause.context)
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([fresh], events: [wrong])))
  }

  func testOmittedUnknownMalformedAndHistoricalInputsDoNotBecomeAccepted() throws {
    let data = try dataset([record()])
    for key in ["focused", "before", "after", "axStart", "admitted", "final"] {
      XCTAssertThrowsError(
        try FixtureTimingReplay.review(mutatePair(data) { $0.removeValue(forKey: key) }))
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(mutatePair(data) { $0["extra"] = "text" }))
    XCTAssertThrowsError(
      try FixtureTimingReplay.review(
        mutatePair(data) { $0["before"] = "safety-snapshot arbitrary" }))
    XCTAssertThrowsError(try FixtureTimingReplay.review(mutatePair(data) { $0["schema"] = 1 })) {
      XCTAssertEqual($0 as? FixtureTimingReplay.Failure, .historicalNonReplayable)
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(data.dropLast()))
    var wrongContext = try record()
    wrongContext.final?.activation = 1
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([wrongContext])))
  }

  func testFailedReaderRetainsOnlyObservedStagesAndIsNotAnAssessment() throws {
    let full = try record()
    var failure = FixtureTimingRecord(index: 1, cohort: .ordinary, requestedDelay: 0, run: run)
    failure.request = full.request
    failure.before = full.before
    failure.admitted = context
    failure.final = context
    failure.outcome = .failed
    for point in FixtureTimingPoint.allCases
    where
      point.rawValue.hasPrefix("before")
      || [.hostAdmission, .admission, .entry, .exit, .publication, .receipt, .terminal].contains(
        point)
    {
      failure.mark(point, at: full.time(point)!)
    }
    let report = try FixtureTimingReplay.review(dataset([failure]))
    XCTAssertEqual(report.failed, 1)
    XCTAssertEqual(report.assessed, 0)
    XCTAssertNil(failure.metrics["evidenceAge"])
    XCTAssertNil(failure.time(.afterStart))
  }

  func testPredeclaredOutputBudgetAndRicherEnvelopeCap() throws {
    XCTAssertEqual(FixtureTimingBudget.reservedBytes, 255488)
    XCTAssertLessThanOrEqual(FixtureTimingBudget.reservedBytes, FixtureTimingBudget.outputBytes)
    XCTAssertEqual(FixtureTimingBudget.cohortAttempts.values.reduce(0, +), 28)
    XCTAssertEqual(
      (0..<16).map { FixtureTimingBudget.phase(cohort: .invalidation, offset: $0) },
      [
        .pause, .recovery, .pause, .recovery, .pause, .recovery, .pause, .recovery,
        .sheet, .recovery, .sheet, .recovery, .sheet, .recovery, .failureProbe, .recovery,
      ])
    var collector = FixtureTimingCollector()
    XCTAssertThrowsError(
      try collector.append(
        String(repeating: "x", count: 6144), maximumBytes: FixtureTimingBudget.pairBytes))
    collector.close(orderly: true, passed: true)
    let terminal = try JSONSerialization.jsonObject(with: collector.bytes) as! [String: Any]
    XCTAssertEqual(terminal["complete"] as? Bool, false)
    XCTAssertEqual(terminal["calibrationSuitable"] as? Bool, false)
    XCTAssertLessThan(collector.bytes.count, 512)
  }

  func testFullDeclaredScheduleReplaysEpisodesAndEightFreshRecoveries() throws {
    var records: [FixtureTimingRecord] = []
    var events: [FixtureTimingEvent] = []
    var authority = FixtureHostAuthority(context: context)
    var state: UInt64 = 2
    for cohort in FixtureTimingCohort.allCases {
      for offset in 0..<FixtureTimingBudget.cohortAttempts[cohort.rawValue]! {
        let index = records.count + 1
        let delay =
          cohort == .dispatch || cohort == .assessment ? [0.0, 0.05, 0.2, 0.5][offset] : 0
        var value = try record(
          index: index, cohort: cohort, delay: delay, changes: ["stateRevision": String(state)])
        value.phase = FixtureTimingBudget.phase(cohort: cohort, offset: offset)
        value.admitted = authority.context
        if value.phase == .pause {
          authority.update(paused: true)
          events.append(
            FixtureTimingEvent(
              code: "pause", time: value.time(.inputsReady)! + 0.5,
              revocation: authority.context.revocation, pending: value.request,
              context: authority.context))
          authority.update(paused: false)
          events.append(
            FixtureTimingEvent(
              code: "resume", time: value.time(.inputsReady)! + 1,
              revocation: authority.context.revocation, pending: value.request,
              context: authority.context))
          value.assessment = .contextRevoked
          value.outcome = .revoked
        } else if value.phase == .sheet {
          state += 2
          value.after = try snapshot(
            request: value.request! + 1,
            start: value.time(.afterStart)!, end: value.time(.afterEnd)!,
            changes: ["stateRevision": String(state)])
          value.assessment = .sourceChanged
          value.outcome = .rejected
        } else if value.phase == .failureProbe {
          var failure = FixtureTimingRecord(
            index: index, cohort: cohort, requestedDelay: 0, run: run)
          failure.phase = .failureProbe
          failure.request = value.request
          failure.before = value.before
          failure.admitted = authority.context
          failure.outcome = .failed
          for point in FixtureTimingPoint.allCases
          where point.rawValue.hasPrefix("before")
            || [.hostAdmission, .admission, .entry, .exit, .publication, .receipt, .terminal]
              .contains(point)
          { failure.mark(point, at: value.time(point)!) }
          value = failure
        }
        value.final = authority.context
        records.append(value)
      }
    }
    let report = try FixtureTimingReplay.review(dataset(records, events: events))
    XCTAssertTrue(report.complete)
    XCTAssertTrue(report.calibrationSuitable)
    XCTAssertEqual(report.attempts, 28)
    XCTAssertEqual(report.assessed, 27)
    XCTAssertEqual(report.failed, 1)
    XCTAssertEqual(
      report.outcomes, ["historicalConsistent": 20, "contextRevoked": 4, "sourceChanged": 3])
    XCTAssertEqual(records.filter { $0.phase == .recovery && $0.expectedOutcome }.count, 8)
    // A deliberately unsupported first observation is replayable but never a calibration dataset.
    records[0] = try record(changes: ["synthetic": "true", "scenario": "tree-ordinary"])
    records[0].phase = .exclusion
    records[0].assessment = .unsupported
    records[0].outcome = .rejected
    let exclusion = try FixtureTimingReplay.review(
      dataset(records, events: events, exclusion: true))
    XCTAssertTrue(exclusion.complete)
    XCTAssertFalse(exclusion.calibrationSuitable)
    XCTAssertEqual(exclusion.outcomes["unsupported"], 1)
    XCTAssertEqual(exclusion.exclusions["synthetic"], 2)
  }

  func testForgedFailureCompletionAndHostEventOrderingReject() throws {
    var value = try record()
    value.outcome = .failed
    value.assessment = nil
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([value])))
    let sameTime = FixtureTimingEvent(
      code: "activation", time: value.time(.hostAdmission)!, revocation: 1,
      pending: value.request, context: context)
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([record()], events: [sameTime])))
    let wrongRun = FixtureTimingEvent(
      code: "activation", time: 65, revocation: 1, pending: value.request,
      context: FixtureUseContext(expected: try FixtureWindowIdentity(run: UUID(), serial: 1)))
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([record()], events: [wrongRun])))
    let data = try dataset([record()])
    XCTAssertThrowsError(
      try FixtureTimingReplay.review(
        mutatePair(data) {
          var times = $0["times"] as! [String: Double]
          times.removeValue(forKey: "entry")
          $0["times"] = times
        }))
  }

  func testSnapshotWatermarksAndNestedContextVocabularyRejectTampering() throws {
    let first = try record()
    var stale = try record(index: 2)
    stale.before = try snapshot(
      request: stale.request!, start: stale.time(.beforeStart)!,
      end: stale.time(.beforeEnd)!, changes: ["sequence": "1"])
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([first, stale])))
    var regressing = try record(index: 2, changes: ["stateRevision": "1"])
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([first, regressing])))
    regressing = try record(index: 2)
    regressing.request = 1
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset([first, regressing])))
    let data = try dataset([first])
    XCTAssertThrowsError(
      try FixtureTimingReplay.review(
        mutatePair(data) {
          var context = $0["final"] as! [String: Any]
          context["unknown"] = "text"
          $0["final"] = context
        }))
    XCTAssertThrowsError(try FixtureTimingReplay.review(Data(repeating: 10, count: 262145)))
    var oversized = try record()
    let tooLong = "42." + String(repeating: "0", count: 1100) + "1"
    oversized.before = try snapshot(request: 1, start: 0, end: 44, changes: ["start": tooLong])
    oversized.mark(.beforeStart, at: oversized.before!.startedAt)
    XCTAssertGreaterThan(oversized.before!.line.utf8.count, 1280)
    XCTAssertFalse(oversized.valid)
  }
}
