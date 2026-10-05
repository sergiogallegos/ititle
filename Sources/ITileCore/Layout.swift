/// Logical points in desktop coordinates: x rightward, y downward.
public struct Rect: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public enum Axis: Sendable { case horizontal, vertical }

/// Session-local identifiers supplied by a future platform registry.
public indirect enum LayoutNode: Sendable {
  case window(Int)
  case split(axis: Axis, ratio: Double, first: LayoutNode, second: LayoutNode)
}

public enum LayoutError: Error, Equatable {
  case invalidBounds, invalidGap, invalidRatio, insufficientSpace
  case duplicateWindow(Int)
}

/// Geometry only: no window discovery, minimum-size negotiation, or pixel snapping yet.
public enum LayoutEngine {
  public static func frames(for tree: LayoutNode, in bounds: Rect, gap: Double = 0) throws -> [Int:
    Rect]
  {
    guard
      [
        bounds.x, bounds.y, bounds.width, bounds.height,
        bounds.x + bounds.width, bounds.y + bounds.height,
      ].allSatisfy({ $0.isFinite }),
      bounds.width > 0, bounds.height > 0
    else { throw LayoutError.invalidBounds }
    guard gap.isFinite, gap >= 0 else { throw LayoutError.invalidGap }
    var result: [Int: Rect] = [:]
    func visit(_ node: LayoutNode, _ rect: Rect) throws {
      switch node {
      case .window(let id):
        guard result[id] == nil else { throw LayoutError.duplicateWindow(id) }
        result[id] = rect
      case .split(let axis, let ratio, let first, let second):
        guard ratio.isFinite, ratio > 0, ratio < 1 else { throw LayoutError.invalidRatio }
        let extent = axis == .horizontal ? rect.width : rect.height
        let available = extent - gap
        let leading = available * ratio
        let trailing = available - leading
        guard leading > 0, trailing > 0 else { throw LayoutError.insufficientSpace }
        if axis == .horizontal {
          try visit(first, Rect(x: rect.x, y: rect.y, width: leading, height: rect.height))
          try visit(
            second, Rect(x: rect.x + leading + gap, y: rect.y, width: trailing, height: rect.height)
          )
        } else {
          try visit(first, Rect(x: rect.x, y: rect.y, width: rect.width, height: leading))
          try visit(
            second, Rect(x: rect.x, y: rect.y + leading + gap, width: rect.width, height: trailing))
        }
      }
    }
    try visit(tree, bounds)
    return result
  }
}
