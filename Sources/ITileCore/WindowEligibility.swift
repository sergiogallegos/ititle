/// Positive observations that exclude a window from the proposed ordinary-window scope.
public enum WindowExclusion: String, Equatable, Sendable {
  case nonWindowRole, nonStandardWindow, minimized, fullscreen, modal
  case positionNotSettable, sizeNotSettable, focusChanged, tokenChanged, sheetPresent, dialogPresent
}

/// Missing evidence blocks enrollment. These codes never contain application content.
public enum UnprovenWindowRequirement: String, Equatable, Sendable {
  case role, subrole, minimizedState, fullscreenState, modalState
  case positionCapability, sizeCapability, focusedContinuity, destructionContinuity
  case directSheets, completeDirectSheetScan, geometry, observationInterval, workerSequence
  case currentDesktopVisibility, nativeTabSafety, nestedDialogSafety
}

/// The generic focused probe has no eligible production scope yet. This assessment
/// explains why; it is neither user consent nor a live mutation permit.
public struct WindowEligibilityAssessment: Equatable, Sendable {
  public let exclusions: [WindowExclusion]
  public let unproven: [UnprovenWindowRequirement]
  let projectionAvailable: Bool

  public var eligibility: ControlEligibility { exclusions.isEmpty ? .unknown : .ineligible }

  public init(evidence: FocusedWindowEvidence) {
    var exclusions: [WindowExclusion] = []
    var unproven: [UnprovenWindowRequirement] = []

    func vocabulary(
      _ read: ProbeRead<String>, expected: String, exclusion: WindowExclusion,
      requirement: UnprovenWindowRequirement
    ) {
      if case .value(let value) = read {
        if value != expected { exclusions.append(exclusion) }
      } else {
        unproven.append(requirement)
      }
    }
    func flag(
      _ read: ProbeRead<Bool>, safe: Bool, exclusion: WindowExclusion,
      requirement: UnprovenWindowRequirement
    ) {
      if case .value(let value) = read {
        if value != safe { exclusions.append(exclusion) }
      } else {
        unproven.append(requirement)
      }
    }
    vocabulary(evidence.role, expected: "AXWindow", exclusion: .nonWindowRole, requirement: .role)
    vocabulary(
      evidence.subrole, expected: "AXStandardWindow", exclusion: .nonStandardWindow,
      requirement: .subrole)
    flag(evidence.minimized, safe: false, exclusion: .minimized, requirement: .minimizedState)
    flag(evidence.fullscreen, safe: false, exclusion: .fullscreen, requirement: .fullscreenState)
    flag(evidence.modal, safe: false, exclusion: .modal, requirement: .modalState)
    flag(
      evidence.positionSettable, safe: true, exclusion: .positionNotSettable,
      requirement: .positionCapability)
    flag(
      evidence.sizeSettable, safe: true, exclusion: .sizeNotSettable,
      requirement: .sizeCapability)
    flag(
      evidence.focusedWindowUnchanged, safe: true, exclusion: .focusChanged,
      requirement: .focusedContinuity)
    if case .value(true) = evidence.destructionNotification {
      // Registration is only a sampled prerequisite, not proof against all races.
    } else {
      unproven.append(.destructionContinuity)
    }
    if evidence.expectedWindowMatches == false { exclusions.append(.tokenChanged) }
    switch evidence.directSheetCount {
    case .value(let count) where count > 0: exclusions.append(.sheetPresent)
    case .value(0): break
    default: unproven.append(.directSheets)
    }
    if !evidence.directSheetScanComplete { unproven.append(.completeDirectSheetScan) }

    if evidence.nestedDialogs.observedSheets > 0, !exclusions.contains(.sheetPresent) {
      exclusions.append(.sheetPresent)
    }
    if evidence.nestedDialogs.observedDialogs > 0 { exclusions.append(.dialogPresent) }

    let geometryValid: Bool
    if case .value(let rect) = evidence.frame {
      geometryValid =
        [rect.x, rect.y, rect.width, rect.height, rect.x + rect.width, rect.y + rect.height]
        .allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
    } else {
      geometryValid = false
    }
    let intervalValid =
      evidence.startedAt.isFinite && evidence.finishedAt.isFinite && evidence.startedAt >= 0
      && evidence.finishedAt >= evidence.startedAt
    let sequenceValid = evidence.workerSequence > 0
    if !geometryValid { unproven.append(.geometry) }
    if !intervalValid { unproven.append(.observationInterval) }
    if !sequenceValid { unproven.append(.workerSequence) }
    projectionAvailable = geometryValid && intervalValid && sequenceValid

    // No generic public-AX proof provider currently establishes these requirements.
    // Equal bounds, frontmost status, role flags, or notification registration
    // cannot remove them. An explicit opt-in does not supply missing evidence.
    unproven.append(contentsOf: [.currentDesktopVisibility, .nativeTabSafety, .nestedDialogSafety])
    self.exclusions = exclusions
    self.unproven = unproven
  }

  public var report: String {
    let excluded = exclusions.isEmpty ? "none" : exclusions.map(\.rawValue).joined(separator: ", ")
    return """
      eligibility-exclusions=\(excluded)
      eligibility-unproven=\(unproven.map(\.rawValue).joined(separator: ", "))
      """
  }
}
