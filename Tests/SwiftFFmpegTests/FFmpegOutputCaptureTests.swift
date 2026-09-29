import XCTest
@testable import SwiftFFmpeg

final class FFmpegOutputCaptureTests: XCTestCase {
    private let marker = " bytes truncated ...]"

    func testLongLogKeepsItsStartAndEnd() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftffmpeg-long-log-\(UUID().uuidString).mp4").path
        defer { try? FileManager.default.removeItem(atPath: output) }

        let result = try SwiftFFmpeg.executeDetailed([
            "-nostdin", "-y", "-loglevel", "debug", "-debug_ts",
            "-f", "lavfi", "-i", "testsrc2=duration=20:size=64x64:rate=25",
            "-c:v", "mpeg4", output,
        ])

        let lines = result.stderr.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        XCTAssertLessThan(result.stderr.utf8.count, 64 * 1024)
        XCTAssertEqual(lines.first, "Splitting the commandline.")
        XCTAssertEqual(lines.filter { $0.hasPrefix("[... ") && $0.hasSuffix(marker) }.count, 1)
        XCTAssertEqual(lines.last, "Exiting with exit code 0")
    }

    func testShortLogIsNotTruncated() throws {
        let result = try SwiftFFmpeg.executeDetailed([
            "-nostdin", "-f", "lavfi", "-i", "testsrc2=duration=1", "-f", "null", "-",
        ])
        XCTAssertTrue(result.stderr.contains("Stream mapping:"), result.stderr)
        XCTAssertFalse(result.stderr.contains(marker))
    }
}
