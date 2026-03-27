import XCTest
@testable import SwiftFFmpeg

final class FFmpegVersionDebugTests: XCTestCase {
    func testFFmpegVersionDebugOutput() throws {
        do {
            let result = try SwiftFFmpeg.executeDetailed(["-version"])

            print("ffmpeg -version stdout:")
            print(result.stdout)
            print("ffmpeg -version stderr:")
            print(result.stderr)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertTrue(
                result.stdout.contains("ffmpeg version") || result.stderr.contains("ffmpeg version"),
                "Expected version output in stdout or stderr.\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
            )
        } catch let SwiftFFmpegError.executionFailed(code, stdout, stderr) {
            print("ffmpeg -version stdout:")
            print(stdout)
            print("ffmpeg -version stderr:")
            print(stderr)
            XCTFail("ffmpeg -version failed with code \(code).\nstdout:\n\(stdout)\nstderr:\n\(stderr)")
        }
    }
}
