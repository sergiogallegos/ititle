/// Read-only evidence, deliberately distinct from proof of tiling eligibility.
public struct FocusedWindowEvidence: Sendable {
  public let token: WindowToken
  public let environmentEpoch: UInt64
  public let workerSequence: UInt64
  public let startedAt: Double
  public let finishedAt: Double
  public let role: ProbeRead<String>
  public let subrole: ProbeRead<String>
  public let minimized: ProbeRead<Bool>
  public let fullscreen: ProbeRead<Bool>
  public let modal: ProbeRead<Bool>
  public let frame: ProbeRead<Rect>
  public let positionSettable: ProbeRead<Bool>
  public let sizeSettable: ProbeRead<Bool>
  public let directSheetCount: ProbeRead<Int>
  public let directSheetScanComplete: Bool
  public let onScreenBounds: OnScreenBoundsEvidence
  public let nestedDialogs: NestedDialogScanSummary
  public let destructionNotification: ProbeRead<Bool>
  public let focusedWindowUnchanged: ProbeRead<Bool>
  public let expectedToken: WindowToken?

  public init(
    token: WindowToken, environmentEpoch: UInt64, workerSequence: UInt64,
    startedAt: Double, finishedAt: Double, role: ProbeRead<String>, subrole: ProbeRead<String>,
    minimized: ProbeRead<Bool>, fullscreen: ProbeRead<Bool>, modal: ProbeRead<Bool>,
    frame: ProbeRead<Rect>, positionSettable: ProbeRead<Bool>, sizeSettable: ProbeRead<Bool>,
    directSheetCount: ProbeRead<Int>, directSheetScanComplete: Bool,
    destructionNotification: ProbeRead<Bool>, focusedWindowUnchanged: ProbeRead<Bool>,
    expectedToken: WindowToken?, nestedDialogs: NestedDialogScanSummary = .notScanned,
    onScreenBounds: OnScreenBoundsEvidence = .notSampled
  ) {
    self.onScreenBounds = onScreenBounds
    self.nestedDialogs = nestedDialogs
    self.token = token
    self.environmentEpoch = environmentEpoch
    self.workerSequence = workerSequence
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.role = role
    self.subrole = subrole
    self.minimized = minimized
    self.fullscreen = fullscreen
    self.modal = modal
    self.frame = frame
    self.positionSettable = positionSettable
    self.sizeSettable = sizeSettable
    self.directSheetCount = directSheetCount
    self.directSheetScanComplete = directSheetScanComplete
    self.destructionNotification = destructionNotification
    self.focusedWindowUnchanged = focusedWindowUnchanged
    self.expectedToken = expectedToken
  }

  public var expectedWindowMatches: Bool? { expectedToken.map { $0 == token } }

  public var eligibilityAssessment: WindowEligibilityAssessment {
    WindowEligibilityAssessment(evidence: self)
  }

  public var eligibility: ControlEligibility { eligibilityAssessment.eligibility }

  public var controlObservation: WindowObservation? {
    guard eligibilityAssessment.projectionAvailable, case .value(let rect) = frame else {
      return nil
    }
    func capability(_ read: ProbeRead<Bool>) -> ControlCapability {
      switch read {
      case .value(true): return .supported
      case .value(false): return .unsupported
      default: return .unknown
      }
    }
    return WindowObservation(
      token: token, frame: rect, eligibility: eligibility,
      positionSettable: capability(positionSettable), sizeSettable: capability(sizeSettable),
      environmentEpoch: environmentEpoch, workerSequence: workerSequence, sampledAt: startedAt)
  }

  public var report: String {
    """
    Focused read-only snapshot: \(token); epoch=\(environmentEpoch); sequence=\(workerSequence)
    role=\(probeDescription(role)); subrole=\(probeDescription(subrole))
    minimized=\(probeDescription(minimized)); fullscreen=\(probeDescription(fullscreen)); modal=\(probeDescription(modal))
    frame=\(probeDescription(frame))
    position-settable=\(probeDescription(positionSettable)); size-settable=\(probeDescription(sizeSettable))
    direct-child-sheets=\(probeDescription(directSheetCount)); scan-complete=\(directSheetScanComplete)
    \(nestedDialogs.report)
    \(onScreenBounds.report)
    destruction-notification=\(probeDescription(destructionNotification))
    focused-window-unchanged-at-checks=\(probeDescription(focusedWindowUnchanged))
    expected-token-match=\(expectedWindowMatches.map(String.init) ?? "not requested")
    eligibility=\(eligibility); visibility/native-tab/nested-sheet safety remains unproven
    \(eligibilityAssessment.report)
    start=\(startedAt); end=\(finishedAt); duration=\(finishedAt - startedAt) s
    Historical, non-atomic evidence; no enrollment, focus action, or window mutation.
    """
  }
}

public enum FocusProbeFailure: Error, Equatable, Sendable {
  case permissionRequired, cancelled, invalidType, limit, identityChanged
  case ax(Int32)
}

public enum FocusedProbeResult: Sendable {
  case observation(FocusedWindowEvidence)
  case failure(FocusProbeFailure)

  public var report: String {
    switch self {
    case .observation(let observation): return observation.report
    case .failure(let reason):
      return "Focused inspection unavailable: \(reason). No enrollment or mutation."
    }
  }
}

/// AppKit supplies process identity and an activation revision, not AX objects.
/// Even A -> inspector -> A during an outstanding request invalidates delivery.
public struct FocusRequestContext: Sendable {
  public let app: AppToken
  public let environmentEpoch: UInt64
  public let activationRevision: UInt64

  public init(app: AppToken, environmentEpoch: UInt64, activationRevision: UInt64) {
    self.app = app
    self.environmentEpoch = environmentEpoch
    self.activationRevision = activationRevision
  }

  public func accepts(
    currentApp: AppToken?, environmentEpoch: UInt64,
    activationRevision: UInt64, trusted: Bool, paused: Bool
  ) -> Bool {
    trusted && !paused && app == currentApp && self.environmentEpoch == environmentEpoch
      && self.activationRevision == activationRevision
  }
}

private func probeDescription<T>(_ value: ProbeRead<T>) -> String {
  switch value {
  case .value(let value): return String(describing: value)
  case .unavailable(let code): return "unknown(AX \(code))"
  case .invalidType: return "unknown(type)"
  }
}
