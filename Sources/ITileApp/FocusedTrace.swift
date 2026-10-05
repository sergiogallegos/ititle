import Foundation
import OSLog

/// Explicit diagnostic launch mode. No window content, paths, or process IDs.
enum FocusedTrace {
  static let enabled = CommandLine.arguments.contains("--trace-focused-probe")
  private static let logger = Logger(subsystem: "local.itile.app", category: "FocusedProbeTrace")

  static func emit(
    _ phase: String, request: UInt64, app: UInt64 = 0, environment: UInt64 = 0,
    trusted: Bool? = nil, uptime: Double = ProcessInfo.processInfo.systemUptime
  ) {
    guard enabled else { return }
    let trust = trusted.map { $0 ? 1 : 0 } ?? -1
    logger.info(
      "phase=\(phase, privacy: .public) request=\(request) app=\(app) environment=\(environment) trust=\(trust) uptime=\(uptime, privacy: .public)"
    )
  }
}
