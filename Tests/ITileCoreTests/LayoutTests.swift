import XCTest

@testable import ITileCore

final class LayoutTests: XCTestCase {
  func testNestedSplitsPreserveGapsAndBoundsOnNegativeOriginDisplay() throws {
    let tree = LayoutNode.split(
      axis: .horizontal, ratio: 0.5, first: .window(1),
      second: .split(axis: .vertical, ratio: 0.5, first: .window(2), second: .window(3)))
    let frames = try LayoutEngine.frames(
      for: tree,
      in: Rect(x: -1000, y: 20, width: 1000, height: 800), gap: 10)
    XCTAssertEqual(frames[1], Rect(x: -1000, y: 20, width: 495, height: 800))
    XCTAssertEqual(frames[2], Rect(x: -495, y: 20, width: 495, height: 395))
    XCTAssertEqual(frames[3], Rect(x: -495, y: 425, width: 495, height: 395))
  }

  func testRejectsDuplicateIdentity() {
    let tree = LayoutNode.split(
      axis: .horizontal, ratio: 0.5, first: .window(1), second: .window(1))
    XCTAssertThrowsError(
      try LayoutEngine.frames(for: tree, in: Rect(x: 0, y: 0, width: 100, height: 100))
    ) {
      XCTAssertEqual($0 as? LayoutError, .duplicateWindow(1))
    }
  }

  func testRejectsInvalidGeometry() {
    let bounds = Rect(x: 0, y: 0, width: 100, height: 100)
    for ratio in [0.0, 1.0, -0.5, Double.nan, Double.infinity] {
      let tree = LayoutNode.split(
        axis: .horizontal, ratio: ratio, first: .window(1), second: .window(2))
      XCTAssertThrowsError(try LayoutEngine.frames(for: tree, in: bounds))
    }
    XCTAssertThrowsError(try LayoutEngine.frames(for: .window(1), in: bounds, gap: -1))
    XCTAssertThrowsError(
      try LayoutEngine.frames(for: .window(1), in: Rect(x: 0, y: 0, width: 0, height: 1)))
    let tree = LayoutNode.split(
      axis: .horizontal, ratio: 0.5, first: .window(1), second: .window(2))
    XCTAssertThrowsError(try LayoutEngine.frames(for: tree, in: bounds, gap: 100))
  }

  func testManyRatiosConserveWidth() throws {
    for value in 1..<100 {
      let tree = LayoutNode.split(
        axis: .horizontal, ratio: Double(value) / 100,
        first: .window(1), second: .window(2))
      let frames = try LayoutEngine.frames(
        for: tree, in: Rect(x: 17, y: -20, width: 1441, height: 900), gap: 7)
      let a = try XCTUnwrap(frames[1])
      let b = try XCTUnwrap(frames[2])
      XCTAssertEqual(a.width + 7 + b.width, 1441, accuracy: 0.000001)
      XCTAssertEqual(b.x + b.width, 1458, accuracy: 0.000001)
      XCTAssertGreaterThan(a.width, 0)
      XCTAssertGreaterThan(b.width, 0)
    }
  }
}
