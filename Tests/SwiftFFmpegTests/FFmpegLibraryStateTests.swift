import XCTest
@testable import SwiftFFmpeg

final class FFmpegLibraryStateTests: XCTestCase {
    private var root: URL!
    private var media: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftffmpeg-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        media = root.appendingPathComponent("media.mp4").path
        _ = try SwiftFFmpeg.executeDetailed([
            "-nostdin", "-y", "-v", "error",
            "-f", "lavfi", "-i", "testsrc2=duration=1:size=64x64:rate=5",
            "-f", "lavfi", "-i", "sine=duration=1",
            "-c:v", "mpeg4", "-c:a", "aac", media,
        ])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testVersionBannerUsesEachToolName() throws {
        let ffmpeg = try SwiftFFmpeg.executeDetailed(["-version"])
        let ffprobe = try SwiftFFmpeg.executeDetailed(["-version"], tool: .ffprobe)
        XCTAssertTrue(ffmpeg.stdout.hasPrefix("ffmpeg version "), ffmpeg.stdout)
        XCTAssertTrue(ffprobe.stdout.hasPrefix("ffprobe version "), ffprobe.stdout)
    }

    func testListingOptionsDoNotRedirectLaterLogsToStdout() throws {
        for listing in [["-version"], ["-bsfs"], ["-encoders"]] {
            _ = try SwiftFFmpeg.executeDetailed(listing)
            _ = try SwiftFFmpeg.executeDetailed(listing, tool: .ffprobe)

            let probe = try SwiftFFmpeg.executeDetailed(
                ["-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", media],
                tool: .ffprobe
            )
            XCTAssertEqual(probe.stdout, "mpeg4\naac\n", "after \(listing)")
            XCTAssertEqual(probe.stderr, "", "after \(listing)")

            let output = root.appendingPathComponent("copy.mp4").path
            let encode = try SwiftFFmpeg.executeDetailed(["-nostdin", "-y", "-i", media, "-c", "copy", output])
            XCTAssertEqual(encode.stdout, "", "after \(listing)")
            XCTAssertTrue(encode.stderr.contains("Stream mapping:"), "after \(listing): \(encode.stderr)")
        }
    }

    func testLogLevelDoesNotLeakIntoLaterRuns() throws {
        _ = try SwiftFFmpeg.executeDetailed(["-v", "quiet", "-show_format", media], tool: .ffprobe)

        let output = root.appendingPathComponent("copy.mp4").path
        let encode = try SwiftFFmpeg.executeDetailed(["-nostdin", "-y", "-i", media, "-c", "copy", output])
        XCTAssertTrue(encode.stderr.contains("Stream mapping:"), encode.stderr)
    }
}
