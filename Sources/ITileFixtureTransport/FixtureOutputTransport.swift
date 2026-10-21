import Darwin

/// Owned-fixture descriptor operations only; no AppKit, AX, or production dependencies.
public enum FixtureOutputTransport {
  public enum Failure: Error { case descriptor, redirect, check }
  public enum ReadResult: Equatable { case bytes, retry, eof, failure }

  public static func classifyRead(count: Int, error: Int32) -> ReadResult {
    if count > 0 { return .bytes }
    if count == 0 { return .eof }
    return error == EAGAIN || error == EINTR ? .retry : .failure
  }

  /// Replaces an existing output descriptor. Stdin and stderr are never targets.
  public static func redirectToNull(_ descriptor: Int32) throws {
    guard descriptor == STDOUT_FILENO || descriptor > STDERR_FILENO,
      fcntl(descriptor, F_GETFD) >= 0
    else { throw Failure.descriptor }
    let sink = open("/dev/null", O_WRONLY | O_CLOEXEC)
    guard sink >= 0 else { throw Failure.redirect }
    defer { close(sink) }
    guard dup2(sink, descriptor) == descriptor else { throw Failure.redirect }
  }

  /// Real, nonblocking pipe check; does not replace this process's standard streams.
  public static func selfCheck() throws {
    var output: [Int32] = [-1, -1]
    guard pipe(&output) == 0 else { throw Failure.check }
    defer { for descriptor in output { close(descriptor) } }
    var input: [Int32] = [-1, -1]
    guard pipe(&input) == 0 else { throw Failure.check }
    defer { for descriptor in input { close(descriptor) } }
    guard output.allSatisfy({ $0 > STDERR_FILENO }), input.allSatisfy({ $0 > STDERR_FILENO }),
      fcntl(output[0], F_SETFL, O_NONBLOCK) == 0,
      fcntl(input[0], F_SETFL, O_NONBLOCK) == 0
    else { throw Failure.check }
    var byte: UInt8 = 42
    let empty = read(output[0], &byte, 1)
    guard classifyRead(count: empty, error: errno) == .retry,
      write(output[1], &byte, 1) == 1, read(output[0], &byte, 1) == 1
    else { throw Failure.check }
    try redirectToNull(output[1])
    guard read(output[0], &byte, 1) == 0,
      write(output[1], &byte, 1) == 1,
      write(input[1], &byte, 1) == 1, read(input[0], &byte, 1) == 1, byte == 42
    else { throw Failure.check }
  }
}
