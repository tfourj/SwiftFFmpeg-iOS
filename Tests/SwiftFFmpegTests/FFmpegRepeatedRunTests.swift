import XCTest
@testable import SwiftFFmpeg

final class FFmpegRepeatedRunTests: XCTestCase {
    func testRepeatedMergeRuns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftffmpeg-reentry", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let video = root.appendingPathComponent("video.mp4").path
        let audio = root.appendingPathComponent("audio.m4a").path
        _ = try SwiftFFmpeg.executeDetailed([
            "-y", "-f", "lavfi", "-i", "testsrc2=duration=1:size=320x240:rate=30",
            "-c:v", "mpeg4", video,
        ])
        _ = try SwiftFFmpeg.executeDetailed([
            "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:a", "aac", audio,
        ])

        for run in 1...10 {
            let output = root.appendingPathComponent("merge-\(run).mp4").path
            let result = try SwiftFFmpeg.executeDetailed([
                "-nostdin", "-y", "-i", video, "-i", audio,
                "-c", "copy", "-map", "0:v:0", "-map", "1:a:0", output,
            ])
            XCTAssertEqual(result.exitCode, 0)
        }
    }
}
