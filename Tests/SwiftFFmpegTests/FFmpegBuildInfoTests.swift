import XCTest
@testable import SwiftFFmpeg

final class FFmpegBuildInfoTests: XCTestCase {
    func testBuildCommitIsAShortCommitOrUnknown() {
        let commit = SwiftFFmpeg.buildCommit
        print("SwiftFFmpeg build commit: \(commit)")
        let pattern = "^([0-9a-f]{7,}(-dirty)?|unknown)$"
        XCTAssertNotNil(commit.range(of: pattern, options: .regularExpression), commit)
    }
}
