import Foundation
import XCTest
@testable import ITilePlatform

final class FixturePipeTests: XCTestCase {
    func testShortReadyEventArrivesBeforeWriterCloses() throws {
        let pipe = Pipe()
        let ready = expectation(description: "ready event delivered while fixture remains alive")
        let readerExited = expectation(description: "reader terminates at EOF")
        let event = Data("ready 123.456\n".utf8)
        let reader = pipe.fileHandleForReading
        defer { try? pipe.fileHandleForWriting.close() }
        Thread.detachNewThread {
            defer { try? reader.close(); readerExited.fulfill() }
            do {
                let first = try FixturePipe.readChunk(from: reader)
                XCTAssertEqual(first, event)
                ready.fulfill()
                let end = try FixturePipe.readChunk(from: reader)
                XCTAssertNil(end)
            } catch { XCTFail("Unexpected pipe error: \(error)") }
        }
        try pipe.fileHandleForWriting.write(contentsOf: event)
        wait(for: [ready], timeout: 2)
        // Keeping this end open until after ready is the launch deadlock regression.
        try pipe.fileHandleForWriting.close()
        wait(for: [readerExited], timeout: 2)
    }

    func testEOFWithoutAReadyEventDoesNotHang() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        XCTAssertNil(try FixturePipe.readChunk(from: pipe.fileHandleForReading))
    }
}
