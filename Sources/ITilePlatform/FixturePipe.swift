import Darwin
import Foundation

/// Blocking transport for the P3 fixture's dedicated reader thread, never the main thread.
public enum FixturePipe {
  /// Return as soon as any bytes are available; a short live-pipe message must not wait
  /// for 1 KiB or EOF. Foundation's read(upToCount:) filled the request on this OS.
  public static func readChunk(from handle: FileHandle) throws -> Data? {
    var bytes = [UInt8](repeating: 0, count: 1024)
    while true {
      let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
      if count > 0 { return Data(bytes.prefix(count)) }
      if count == 0 { return nil }
      if errno == EINTR { continue }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
