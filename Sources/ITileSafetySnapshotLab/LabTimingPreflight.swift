import ApplicationServices
import CryptoKit
import Darwin
import Foundation
import ITileFixtureDiagnostics

func labArtifactHash(_ path: String) throws -> String {
  let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
  defer { try? handle.close() }
  var hash = SHA256()
  var count = 0
  while let data = try handle.read(upToCount: 65536), !data.isEmpty {
    count += data.count
    guard count <= 67_108_864 else { throw FixtureTimingReplay.Failure.bound }
    hash.update(data: data)
  }
  return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Exact CLI trust/artifact declaration before any application or owned child is created.
func runSetupAckDelayPreflight() -> Never {
  do {
    let trusted = AXIsProcessTrusted()
    let object: [String: Any] = [
      "kind": "ackDelayPreflight", "schema": 4, "trusted": trusted,
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "utc": ISO8601DateFormatter().string(from: Date()),
      "labHash": try labArtifactHash(CommandLine.arguments[0]),
      "fixtureHash": try labArtifactHash(
        FileManager.default.currentDirectoryPath
          + "/dist/iTile AX Fixture.app/Contents/MacOS/iTileAXFixture"),
      "fault": FixtureSetupFault.normalizationAckDelayOnce.rawValue,
      "faultSeconds": FixtureAckDelayOnce.seconds,
      "responseSeconds": FixtureAckDelayOnce.responseSeconds,
      "readerSeconds": 5, "deadlineSeconds": 180, "cleanupSeconds": [3, 1],
      "drainSeconds": 5, "attemptLimit": 28, "setupLimit": 14, "eventLimit": 128,
      "pairBytes": 6144, "eventBytes": 512, "setupBytes": 512, "manifestBytes": 1280,
      "faultBytes": 512, "summaryBytes": 14592, "closureBytes": 1024,
      "outputBytes": 262144, "rowLimit": 175, "invocationLimit": 1,
    ]
    var output = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    output.append(10)
    try FileHandle.standardOutput.write(contentsOf: output)
    exit(trusted ? 0 : 1)
  } catch {
    print("{\"kind\":\"ackDelayPreflightFailure\",\"reason\":\"artifactReadOrOutput\"}")
    exit(1)
  }
}
