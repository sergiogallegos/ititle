/// Fixed, content-free reasons why a structural sample was not exhaustive.
public enum NestedDialogScanIssue: String, Equatable, Sendable {
  case notScanned, unsupported, readFailure, invalidType, cycle, depthLimit, nodeLimit
  case budget, cancelled
}

public struct NestedDialogScanSummary: Equatable, Sendable {
  public let observedSheets: Int
  public let observedDialogs: Int
  public let examinedNodes: Int
  public let issues: [NestedDialogScanIssue]

  public static let notScanned = NestedDialogScanSummary(
    observedSheets: 0, observedDialogs: 0, examinedNodes: 0, issues: [.notScanned])

  public var complete: Bool { issues.isEmpty }

  public var report: String {
    let outcomes = issues.isEmpty ? "complete" : issues.map(\.rawValue).joined(separator: ",")
    return
      "nested-structure: sheets=\(observedSheets); dialogs=\(observedDialogs); nodes=\(examinedNodes); outcomes=\(outcomes)"
  }
}

public struct StructuralNodeRead {
  public let role: ProbeRead<String>
  public let subrole: ProbeRead<String>
  public let issues: [NestedDialogScanIssue]

  public init(
    role: ProbeRead<String>, subrole: ProbeRead<String>, issues: [NestedDialogScanIssue] = []
  ) {
    self.issues = issues
    self.role = role
    self.subrole = subrole
  }
}

public struct StructuralChildren<Node> {
  public let nodes: [Node]
  public let truncated: Bool

  public init(nodes: [Node], truncated: Bool) {
    self.nodes = nodes
    self.truncated = truncated
  }
}

/// Synchronous bounded traversal. The platform supplies worker-owned handles;
/// core owns no AX objects, clocks, or threads. Root is the selected window,
/// depth zero; counts include descendants only. Repeated identities are treated
/// conservatively as cycles, including shared links in a graph.
public enum NestedDialogScanner {
  public static func scan<Node>(
    root: Node, maxNodes: Int = 64, maxDepth: Int = 6,
    equal: (Node, Node) -> Bool,
    stop: () -> NestedDialogScanIssue?,
    read: (Node) -> Result<StructuralNodeRead, StructuralScanFailure>,
    children: (Node, Int) -> Result<StructuralChildren<Node>, StructuralScanFailure>
  ) -> NestedDialogScanSummary {
    var issues: [NestedDialogScanIssue] = []
    var sheets = 0
    var dialogs = 0
    var examined = 0
    func record(_ issue: NestedDialogScanIssue) {
      if !issues.contains(issue) { issues.append(issue) }
    }
    guard maxNodes > 0, maxDepth >= 0 else {
      return NestedDialogScanSummary(
        observedSheets: 0, observedDialogs: 0, examinedNodes: 0,
        issues: [maxNodes <= 0 ? .nodeLimit : .depthLimit])
    }
    var seen = [root]
    var pending = [(root, 0)]
    while !pending.isEmpty {
      if let issue = stop() {
        record(issue)
        break
      }
      let (node, depth) = pending.removeLast()
      examined += 1
      if depth > 0 {
        switch read(node) {
        case .failure(let failure): record(failure.issue)
        case .success(let value):
          if case .value("AXSheet") = value.role { sheets += 1 }
          let dialogNames = ["AXDialog", "AXSystemDialog"]
          if case .value(let role) = value.role, dialogNames.contains(role) {
            dialogs += 1
          } else if case .value(let subrole) = value.subrole, dialogNames.contains(subrole) {
            dialogs += 1
          }
          for issue in value.issues { record(issue) }
          for attribute in [value.role, value.subrole] {
            switch attribute {
            case .value: break
            case .invalidType: record(.invalidType)
            case .unavailable:
              if value.issues.isEmpty { record(.readFailure) }
            }
          }
        }
      }
      if let issue = stop() {
        record(issue)
        break
      }
      // Even at a boundary, query at most one child to distinguish a leaf.
      let capacity = depth == maxDepth ? 1 : max(1, maxNodes - seen.count)
      switch children(node, capacity) {
      case .failure(let failure): record(failure.issue)
      case .success(let value):
        if depth == maxDepth {
          if !value.nodes.isEmpty || value.truncated { record(.depthLimit) }
          continue
        }
        if value.truncated { record(.nodeLimit) }
        for child in value.nodes.prefix(capacity) {
          if seen.contains(where: { equal($0, child) }) {
            record(.cycle)
            continue
          }
          guard seen.count < maxNodes else {
            record(.nodeLimit)
            break
          }
          seen.append(child)
          pending.append((child, depth + 1))
        }
        if value.nodes.count > capacity { record(.nodeLimit) }
      }
    }
    return NestedDialogScanSummary(
      observedSheets: sheets, observedDialogs: dialogs, examinedNodes: examined, issues: issues)
  }
}

public struct StructuralScanFailure: Error {
  public let issue: NestedDialogScanIssue

  public init(_ issue: NestedDialogScanIssue) { self.issue = issue }
}
