import XCTest

@testable import ITileCore

final class OnScreenBoundsTests: XCTestCase {
  private let frame = Rect(x: -1920, y: 30, width: 800, height: 600)

  private func window(_ frame: Rect, layer: Int = 0) -> OnScreenWindowMetadata {
    OnScreenWindowMetadata(layer: layer, frame: frame)
  }

  func testSingleMatchAndIdenticalBoundsAreOnlyCandidates() {
    let single = OnScreenBoundsEvidence(frame: frame, windows: [window(frame)])
    XCTAssertEqual(single.boundsCandidates, 1)
    XCTAssertTrue(single.report.contains("singleBoundsCandidate"))
    XCTAssertTrue(single.report.contains("visibility remain unproven"))
    // These could represent two windows, or an on-desktop window with the same
    // geometry as the selected off-desktop AX window. Bounds encode no identity.
    let duplicate = OnScreenBoundsEvidence(frame: frame, windows: [window(frame), window(frame)])
    XCTAssertEqual(duplicate.boundsCandidates, 2)
    XCTAssertTrue(duplicate.report.contains("ambiguousBoundsCandidates"))
  }

  func testEmptyAndNonmatchingSnapshotsDoNotInferOffDesktopState() {
    for entries in [[], [window(Rect(x: 0, y: 30, width: 800, height: 600))]] {
      let evidence = OnScreenBoundsEvidence(frame: frame, windows: entries)
      XCTAssertEqual(evidence.boundsCandidates, 0)
      XCTAssertTrue(evidence.report.contains("noBoundsCandidate"))
      XCTAssertTrue(evidence.report.contains("visibility remain unproven"))
    }
  }

  func testFixedToleranceAndNegativeOrigins() {
    let nearby = Rect(x: frame.x + 1, y: frame.y - 1, width: 801, height: 599)
    let outside = Rect(x: frame.x + 1.01, y: frame.y, width: 800, height: 600)
    let evidence = OnScreenBoundsEvidence(
      frame: frame, windows: [window(nearby), window(outside), window(frame, layer: 1)])
    XCTAssertEqual(evidence.ordinaryEntries, 2)
    XCTAssertEqual(evidence.boundsCandidates, 1)
    XCTAssertTrue(evidence.issues.isEmpty)
  }

  func testInvalidMetadataAndGeometryRemainIncomplete() {
    let invalid = [
      Rect(x: .nan, y: 0, width: 800, height: 600),
      Rect(x: 0, y: 0, width: -800, height: 600),
      Rect(x: 0, y: 0, width: 800, height: 0),
      Rect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 600),
    ]
    for bad in invalid {
      let malformed = OnScreenBoundsEvidence(frame: frame, windows: [window(bad), window(frame)])
      XCTAssertEqual(malformed.boundsCandidates, 1)
      XCTAssertEqual(malformed.issues, [.invalidMetadata])
      let selected = OnScreenBoundsEvidence(frame: bad, windows: [window(frame)])
      XCTAssertEqual(selected.boundsCandidates, 0)
      XCTAssertEqual(selected.issues, [.invalidGeometry])
    }
    let missing = OnScreenBoundsEvidence(
      frame: frame,
      windows: [OnScreenWindowMetadata(layer: nil, frame: frame), .init(layer: 0, frame: nil)])
    XCTAssertEqual(missing.issues, [.invalidMetadata])
    XCTAssertEqual(missing.ordinaryEntries, 1)
  }

  func testLimitsAndIncompleteSamplesRetainCandidates() {
    let limited = OnScreenBoundsEvidence(
      frame: frame, windows: [window(frame), window(frame)], entryLimit: 1)
    XCTAssertEqual(limited.examinedEntries, 1)
    XCTAssertEqual(limited.boundsCandidates, 1)
    XCTAssertEqual(limited.issues, [.entryLimit])
    XCTAssertTrue(limited.report.contains("result=incomplete"))
    let stopped = OnScreenBoundsEvidence(frame: frame, windows: [window(frame)], entryLimit: 0)
    XCTAssertEqual(stopped.examinedEntries, 0)
    XCTAssertEqual(stopped.issues, [.entryLimit])
    for issue in [OnScreenBoundsIssue.budget, .cancelled, .metadataUnavailable] {
      let sample = OnScreenBoundsEvidence(frame: frame, windows: [window(frame)], issues: [issue])
      XCTAssertEqual(sample.boundsCandidates, 1)
      XCTAssertEqual(sample.issues, [issue])
      XCTAssertTrue(sample.report.contains("result=incomplete"))
    }
    XCTAssertTrue(OnScreenBoundsEvidence.notSampled.report.contains("notSampled"))
  }
}
