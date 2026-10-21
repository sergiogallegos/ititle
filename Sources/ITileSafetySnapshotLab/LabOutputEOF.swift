import ApplicationServices
import Darwin
import Foundation
import ITileFixtureDiagnostics
import ITileFixtureTransport

func runOutputEOFSelfCheck() -> Never {
  do {
    try FixtureOutputTransport.selfCheck()
    print(
      "{\"kind\":\"outputEOFSelfCheck\",\"passed\":true,\"synthetic\":true,\"nativeCollection\":false}"
    )
    exit(0)
  } catch {
    print(
      "{\"kind\":\"outputEOFSelfCheck\",\"passed\":false,\"synthetic\":true,\"nativeCollection\":false}"
    )
    exit(1)
  }
}

/// Diagnostic-only artifact/trust declaration. No application or child is created.
func runOutputEOFPreflight() -> Never {
  do {
    let trusted = AXIsProcessTrusted()
    let object: [String: Any] = [
      "kind": "outputEOFPreflight", "schema": 6, "trusted": trusted,
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "utc": ISO8601DateFormatter().string(from: Date()),
      "labHash": try labArtifactHash(CommandLine.arguments[0]),
      "fixtureHash": try labArtifactHash(
        FileManager.default.currentDirectoryPath
          + "/dist/iTile AX Fixture.app/Contents/MacOS/iTileAXFixture"),
      "fault": FixtureSetupFault.normalizationOutputEOFOnce.rawValue,
      "eventSources": FixtureEventSourceContract.environmentCallbacks.rawValue,
      "responseSeconds": 5, "readerSeconds": 5, "deadlineSeconds": 180,
      "cleanupSeconds": [3, 1], "drainSeconds": 5, "attemptLimit": 28,
      "setupLimit": 14, "eventLimit": 128, "inputEventLimit": 512, "pendingLineBytes": 8192,
      "pairBytes": 6144, "eventBytes": 512, "setupBytes": 512, "manifestBytes": 1280,
      "faultBytes": 512, "summaryBytes": 14592, "closureBytes": 1024,
      "outputBytes": 262144, "rowLimit": 175, "invocationLimit": 1,
    ]
    var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    data.append(10)
    try FileHandle.standardOutput.write(contentsOf: data)
    exit(trusted ? 0 : 1)
  } catch {
    print("{\"kind\":\"outputEOFPreflightFailure\",\"reason\":\"artifactReadOrOutput\"}")
    exit(1)
  }
}
