import Darwin
import Foundation

/// Explicitly packaged lab mode only. CLI runs retain their caller-owned stdout.
/// Reports contain the fixed laboratory vocabulary, never titles/keys/document paths.
func preparePermissionAppReport() throws {
  let project = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
  guard FileManager.default.changeCurrentDirectoryPath(project.path) else {
    throw CocoaError(.fileReadNoSuchFile)
  }
  let report = project.appendingPathComponent("dist/safety-permission-lab.log")
  let descriptor = open(report.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600))
  guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
  defer { close(descriptor) }
  guard dup2(descriptor, STDOUT_FILENO) >= 0 else { throw CocoaError(.fileWriteUnknown) }
  setbuf(stdout, nil)
}
