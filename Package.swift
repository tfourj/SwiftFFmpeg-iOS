// swift-tools-version: 5.9
import Foundation
import PackageDescription

struct BinaryReleaseMetadata: Decodable {
    let version: String
    let url: String
    let checksum: String
}

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localXCFrameworkPath = packageRoot.appendingPathComponent("FFmpeg.xcframework").path
let releaseMetadataPath = packageRoot.appendingPathComponent("Package.release.json")

func loadBinaryReleaseMetadata() -> BinaryReleaseMetadata {
    guard FileManager.default.fileExists(atPath: releaseMetadataPath.path) else {
        fatalError(
            """
            Missing FFmpeg.xcframework and Package.release.json.
            Build locally with ./Scripts/build-ffmpeg-ios.sh or publish a binary release first.
            """
        )
    }

    do {
        let data = try Data(contentsOf: releaseMetadataPath)
        let metadata = try JSONDecoder().decode(BinaryReleaseMetadata.self, from: data)

        guard !metadata.version.isEmpty, !metadata.url.isEmpty, !metadata.checksum.isEmpty else {
            fatalError("Package.release.json is missing required release metadata.")
        }

        return metadata
    } catch {
        fatalError("Failed to load Package.release.json: \(error)")
    }
}

let ffmpegTarget: Target = {
    if FileManager.default.fileExists(atPath: localXCFrameworkPath) {
        return .binaryTarget(
            name: "FFmpeg",
            path: "FFmpeg.xcframework"
        )
    }

    let metadata = loadBinaryReleaseMetadata()
    return .binaryTarget(
        name: "FFmpeg",
        url: metadata.url,
        checksum: metadata.checksum
    )
}()

let package = Package(
    name: "SwiftFFmpeg",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftFFmpeg",
            targets: ["SwiftFFmpeg"]
        ),
    ],
    targets: [
        // Uses a local XCFramework during development and release metadata for published packages.
        ffmpegTarget,
        // C shim that calls into the FFmpeg CLI-style API
        .target(
            name: "CFFmpegCLI",
            dependencies: ["FFmpeg"],
            path: "Sources/CFFmpegCLI",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv")
            ]
        ),
        // Swift wrapper you'll use in your app
        .target(
            name: "SwiftFFmpeg",
            dependencies: ["CFFmpegCLI"],
            path: "Sources/SwiftFFmpeg",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv")
            ]
        )
    ]
)
