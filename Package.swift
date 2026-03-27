// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localXCFrameworkPath = packageRoot.appendingPathComponent("FFmpeg.xcframework").path
let testsPath = packageRoot.appendingPathComponent("Tests/SwiftFFmpegTests").path

guard FileManager.default.fileExists(atPath: localXCFrameworkPath) else {
    fatalError(
        """
        Missing FFmpeg.xcframework.
        Download and extract SwiftFFmpeg-iOS.zip from Releases or build locally with ./Scripts/build-ffmpeg-ios.sh.
        """
    )
}

var package = Package(
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
        .binaryTarget(
            name: "FFmpeg",
            path: "FFmpeg.xcframework"
        ),
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

if FileManager.default.fileExists(atPath: testsPath) {
    package.targets.append(
        .testTarget(
            name: "SwiftFFmpegTests",
            dependencies: ["SwiftFFmpeg"],
            path: "Tests/SwiftFFmpegTests"
        )
    )
}
