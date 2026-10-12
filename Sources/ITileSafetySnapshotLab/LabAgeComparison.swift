import CryptoKit
import Darwin
import Foundation
import ITileFixtureDiagnostics

/// Offline adapter: bounded files and cryptographic identities, before trust/UI setup.
func runAgeComparison(arguments: [String]) -> Never {
  signal(SIGPIPE, SIG_IGN)
  let output: FixtureAgeComparisonOutput
  do {
    guard arguments.count == 5 else { throw FixtureAgeComparison.Failure.inputSet }
    func read(_ path: String, maximumBytes: Int) throws -> Data {
      let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
      defer { try? handle.close() }
      var data = Data()
      while let chunk = try handle.read(upToCount: 16384), !chunk.isEmpty {
        guard data.count + chunk.count <= maximumBytes else {
          throw FixtureAgeComparison.Failure.inputRead
        }
        data.append(chunk)
      }
      return data
    }
    func digest(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    let evaluatorHash = try digest(read(arguments[0], maximumBytes: 67_108_864))
    var inputs: [FixtureAgeInput] = []
    for (index, dataset) in FixtureAgeDataset.allCases.enumerated() {
      inputs.append(
        FixtureAgeInput(
          dataset: dataset,
          data: try read(arguments[index + 2], maximumBytes: FixtureTimingBudget.outputBytes)))
    }
    output = FixtureAgeComparison.evaluate(inputs, evaluatorHash: evaluatorHash, digest: digest)
  } catch {
    output = FixtureAgeComparison.failure(
      (error as? FixtureAgeComparison.Failure) ?? .inputRead)
  }
  do { try FileHandle.standardOutput.write(contentsOf: output.bytes) } catch { exit(1) }
  exit(output.complete ? 0 : 1)
}
