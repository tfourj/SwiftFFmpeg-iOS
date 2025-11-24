// swift-tools-version: 5.9
import PackageDescription

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
        // Prebuilt FFmpeg XCFramework (created by Scripts/build-ffmpeg-ios.sh)
        .binaryTarget(
            name: "FFmpeg",
            path: "FFmpeg.xcframework"
        ),
        // C shim that calls into the FFmpeg CLI-style API
        .target(
            name: "CFFmpegCLI",
            dependencies: ["FFmpeg"],
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
        .testTarget(
            name: "SwiftFFmpegTests",
            dependencies: ["SwiftFFmpeg"]
        )
    ]
)