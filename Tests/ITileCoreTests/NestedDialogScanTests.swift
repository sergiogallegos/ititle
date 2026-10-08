import XCTest

@testable import ITileCore

final class NestedDialogScanTests: XCTestCase {
  private func scan(
    edges: [Int: [Int]], roles: [Int: String] = [:], subroles: [Int: String] = [:],
    maxNodes: Int = 64, maxDepth: Int = 6,
    failures: [Int: NestedDialogScanIssue] = [:], stop: () -> NestedDialogScanIssue? = { nil }
  ) -> NestedDialogScanSummary {
    NestedDialogScanner.scan(
      root: 0, maxNodes: maxNodes, maxDepth: maxDepth, equal: ==, stop: stop,
      read: { node in
        .success(
          StructuralNodeRead(
            role: .value(roles[node] ?? "other-role"),
            subrole: .value(subroles[node] ?? "other-role")))
      },
      children: { node, limit in
        if let failure = failures[node] { return .failure(StructuralScanFailure(failure)) }
        let children = edges[node] ?? []
        return .success(
          StructuralChildren(
            nodes: Array(children.prefix(limit)), truncated: children.count > limit))
      })
  }

  func testNestedSheetsAndWindowDialogSubrolesAreDetectedOnce() {
    let summary = scan(
      edges: [0: [1], 1: [2, 3, 4]],
      roles: [2: "AXSheet", 3: "AXWindow", 4: "AXDialog"],
      subroles: [3: "AXSystemDialog", 4: "AXDialog"])
    XCTAssertEqual(summary.observedSheets, 1)
    XCTAssertEqual(summary.observedDialogs, 2)
    XCTAssertEqual(summary.examinedNodes, 5)
    XCTAssertTrue(summary.complete)
  }

  func testTabGroupsAreCountedWithoutTreatingRadioButtonsAsTabs() {
    let summary = scan(
      edges: [0: [1], 1: [2, 3, 4]],
      roles: [1: "AXTabGroup", 2: "AXRadioButton", 3: "AXTabGroup", 4: "AXSheet"])
    XCTAssertEqual(summary.observedTabGroups, 2)
    XCTAssertEqual(summary.observedSheets, 1)
    XCTAssertEqual(summary.observedDialogs, 0)
    XCTAssertTrue(summary.complete)
    XCTAssertTrue(summary.report.contains("tab-groups=2"))
  }

  func testIncompleteTabGroupSamplesRetainPositiveEvidence() {
    let cycle = scan(edges: [0: [1], 1: [1]], roles: [1: "AXTabGroup"])
    XCTAssertEqual(cycle.observedTabGroups, 1)
    XCTAssertEqual(cycle.issues, [.cycle])
    let unsupported = scan(
      edges: [0: [1]], roles: [1: "AXTabGroup"], failures: [1: .unsupported])
    XCTAssertEqual(unsupported.observedTabGroups, 1)
    XCTAssertFalse(unsupported.complete)
    let limited = scan(
      edges: [0: [1], 1: [2]], roles: [2: "AXTabGroup"], maxDepth: 1)
    XCTAssertEqual(limited.observedTabGroups, 0)
    XCTAssertEqual(limited.issues, [.depthLimit])
    var checks = 0
    let budget = scan(
      edges: [0: [1]], roles: [1: "AXTabGroup"],
      stop: {
        checks += 1
        return checks >= 4 ? .budget : nil
      })
    XCTAssertEqual(budget.observedTabGroups, 1)
    XCTAssertEqual(budget.issues, [.budget])
  }

  func testCycleAndSharedLinksNeverProveAbsence() {
    for edges in [[0: [1], 1: [0]], [0: [1, 2], 1: [2]]] {
      let summary = scan(edges: edges)
      XCTAssertEqual(summary.issues, [.cycle])
      XCTAssertFalse(summary.complete)
      XCTAssertLessThanOrEqual(summary.examinedNodes, 3)
    }
  }

  func testNodeAndDepthLimitsPreservePositiveEvidence() {
    let nodes = scan(edges: [0: [1, 2, 3]], roles: [1: "AXSheet"], maxNodes: 2)
    XCTAssertEqual(nodes.observedSheets, 1)
    XCTAssertEqual(nodes.examinedNodes, 2)
    XCTAssertEqual(nodes.issues, [.nodeLimit])
    let depth = scan(edges: [0: [1], 1: [2]], roles: [1: "AXDialog"], maxDepth: 1)
    XCTAssertEqual(depth.observedDialogs, 1)
    XCTAssertEqual(depth.issues, [.depthLimit])
    XCTAssertTrue(scan(edges: [0: [1]], maxDepth: 1).complete)
  }

  func testUnsupportedMalformedAndFailedBranchesRemainIncomplete() {
    for issue in [NestedDialogScanIssue.unsupported, .invalidType, .readFailure] {
      let summary = scan(edges: [0: [1]], roles: [1: "AXSheet"], failures: [1: issue])
      XCTAssertEqual(summary.observedSheets, 1)
      XCTAssertEqual(summary.issues, [issue])
      XCTAssertFalse(summary.complete)
    }
  }

  func testBudgetAndCancellationStopBeforeAnyReads() {
    for issue in [NestedDialogScanIssue.budget, .cancelled] {
      let summary = scan(edges: [0: [1]], stop: { issue })
      XCTAssertEqual(summary.examinedNodes, 0)
      XCTAssertEqual(summary.issues, [issue])
      XCTAssertFalse(summary.complete)
    }
  }

  func testBudgetAfterFindingRetainsPositiveCounts() {
    var checks = 0
    let summary = scan(
      edges: [0: [1]], roles: [1: "AXSheet"],
      stop: {
        checks += 1
        return checks >= 4 ? .budget : nil
      })
    XCTAssertEqual(summary.observedSheets, 1)
    XCTAssertEqual(summary.issues, [.budget])
  }

  func testUnknownRoleCannotProveAbsence() {
    let summary = NestedDialogScanner.scan(
      root: 0, equal: ==, stop: { nil },
      read: { _ in .success(StructuralNodeRead(role: .invalidType, subrole: .value("AXDialog"))) },
      children: { node, _ in
        .success(StructuralChildren(nodes: node == 0 ? [1] : [], truncated: false))
      })
    XCTAssertEqual(summary.observedDialogs, 1)
    XCTAssertFalse(summary.complete)
  }
}
