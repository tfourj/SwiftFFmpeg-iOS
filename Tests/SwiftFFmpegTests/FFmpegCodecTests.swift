import XCTest
@testable import SwiftFFmpeg

final class FFmpegCodecTests: XCTestCase {
    private func temporaryPath(_ ext: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftffmpeg-codec-\(UUID().uuidString).\(ext)").path
    }

    func testDav1dDecoderIsAvailable() throws {
        let result = try SwiftFFmpeg.executeDetailed(["-hide_banner", "-decoders"])
        XCTAssertTrue(result.stdout.contains(" libdav1d "), result.stdout)
    }

    func testDashDemuxerIsAvailable() throws {
        let result = try SwiftFFmpeg.executeDetailed(["-hide_banner", "-demuxers"])
        XCTAssertTrue(result.stdout.contains(" dash "), result.stdout)
    }

    func testWebPEncodesStillImage() throws {
        let output = temporaryPath("webp")
        defer { try? FileManager.default.removeItem(atPath: output) }

        _ = try SwiftFFmpeg.executeDetailed([
            "-nostdin", "-y", "-f", "lavfi", "-i", "testsrc2=size=64x64",
            "-frames:v", "1", "-c:v", "libwebp", output,
        ])
        XCTAssertGreaterThan(try fileSize(output), 0)
    }

    func testWebPEncodesAnimation() throws {
        let output = temporaryPath("webp")
        defer { try? FileManager.default.removeItem(atPath: output) }

        _ = try SwiftFFmpeg.executeDetailed([
            "-nostdin", "-y", "-f", "lavfi", "-i", "testsrc2=duration=1:size=64x64:rate=5",
            "-c:v", "libwebp_anim", "-loop", "0", output,
        ])
        XCTAssertGreaterThan(try fileSize(output), 0)
    }

    func testSoxrResamplesAudio() throws {
        let result = try SwiftFFmpeg.executeDetailed([
            "-nostdin", "-f", "lavfi", "-i", "sine=duration=1:sample_rate=48000",
            "-af", "aresample=44100:resampler=soxr", "-f", "null", "-",
        ])
        XCTAssertTrue(result.stderr.contains("44100 Hz"), result.stderr)
    }

    private func fileSize(_ path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? Int) ?? 0
    }
}
