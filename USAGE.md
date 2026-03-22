# Usage

## Basic Conversion

```swift
import SwiftFFmpeg

do {
    let (exitCode, output) = try SwiftFFmpeg.execute([
        "-i", inputPath,
        "-c", "copy",
        outputPath
    ])
    print("Conversion completed with exit code: \(exitCode)")
    print(output)
} catch SwiftFFmpegError.executionFailed(let code, let stdout, let stderr) {
    print("FFmpeg failed with code: \(code)")
    print(stdout)
    print(stderr)
}
```

## Get FFmpeg Version

```swift
let (_, output) = try SwiftFFmpeg.execute(["-version"], tool: .ffmpeg)
print(output)

let (_, version) = try SwiftFFmpeg.execute(["-version"])
print(version)
```

## Using ffprobe

```swift
let (_, version) = try SwiftFFmpeg.execute(["-version"], tool: .ffprobe)
print(version)

let (_, formatInfo) = try SwiftFFmpeg.execute(
    ["-v", "error", "-show_format", "video.mp4"],
    tool: .ffprobe
)
print(formatInfo)

let (_, streamInfo) = try SwiftFFmpeg.execute(
    ["-v", "error", "-show_streams", "-of", "json", "video.mp4"],
    tool: .ffprobe
)
print(streamInfo)

let (_, durationStr) = try SwiftFFmpeg.execute(
    ["-v", "error", "-show_entries", "format=duration",
     "-of", "default=noprint_wrappers=1:nokey=1", "video.mp4"],
    tool: .ffprobe
)
if let duration = Double(durationStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
    print("Duration: \(duration) seconds")
}
```

## Extract Audio

```swift
let (exitCode, output) = try SwiftFFmpeg.execute([
    "-i", videoPath,
    "-vn",
    "-c:a", "libmp3lame",
    "-b:a", "192k",
    audioPath
])
print(exitCode)
print(output)
```

## Merge Video and Audio

```swift
let (exitCode, output) = try SwiftFFmpeg.execute([
    "-i", videoPath,
    "-i", audioPath,
    "-c:v", "copy",
    "-c:a", "copy",
    outputPath
])
print(exitCode)
print(output)
```

## Logging

```swift
SwiftFFmpeg.setLogLevel(.info)
SwiftFFmpeg.setLogHandler { level, message in
    print("[\(level)] \(message)")
}

try SwiftFFmpeg.execute([...])

SwiftFFmpeg.setLogHandler(nil)
```

## API Reference

| Method | Description |
|--------|-------------|
| `execute([String], tool: FFmpegTool)` | Run FFmpeg or ffprobe and return `(exitCode, output)`. Throws on non-zero exit. |
| `executeDetailed([String], tool: FFmpegTool)` | Run FFmpeg or ffprobe and return `exitCode`, `stdout`, and `stderr`. |
| `setLogLevel(FFmpegLogLevel)` | Set FFmpeg log verbosity. |
| `setLogHandler((level, message) -> Void)` | Receive FFmpeg log messages. Pass `nil` to disable. |
| `requestCancel()` | Request cancellation of the active ffmpeg or ffprobe execution. |
