# SwiftFFmpeg-iOS

Scripts that will build a Swift package that wraps FFmpeg for iOS. Run FFmpeg commands directly from Swift code.

**Features:**
- FFmpeg as an XCFramework (arm64 device + arm64 simulator)
- Simple `SwiftFFmpeg.execute()` API
- Logging support

---

## Quick Start

### 1. Build the Framework

```bash
./Scripts/build-ffmpeg-ios.sh
```

This creates `FFmpeg.xcframework` in the project root.

### 2. Add to Your Project

**Swift Package Manager (Recommended):**

In Xcode: **File → Add Package Dependencies...** → Enter the repository URL

**Manual:**

Drag `FFmpeg.xcframework` into your Xcode project and set to **Embed & Sign**

### 3. Use It

```swift
import SwiftFFmpeg

// Run any FFmpeg command (always captures output)
let (exitCode, output) = try SwiftFFmpeg.execute([
    "-i", "input.mp4",
    "-c:v", "copy",
    "-c:a", "aac",
    "output.mp4"
])
```

---

## Build Options

```bash
# Full build (clean + LAME + FFmpeg + XCFramework)
./Scripts/build-ffmpeg-ios.sh

# Incremental build (skip cleaning)
./Scripts/build-ffmpeg-ios.sh --no-clean

# Build only specific parts
./Scripts/build-ffmpeg-ios.sh --lame-only      # Only LAME
./Scripts/build-ffmpeg-ios.sh --ffmpeg-only    # Only FFmpeg
./Scripts/build-ffmpeg-ios.sh --xcf-only       # Only XCFramework

# Show help
./Scripts/build-ffmpeg-ios.sh --help
```

**Build Report:**
A clean build summary is automatically generated at `build-report.txt` in the project root. This file contains only high-level progress information (section starts, completions, errors) without the verbose compilation output that appears on stdout.

**Build Structure:**
```
Scripts/
├── build-ffmpeg-ios.sh          # Main build script
├── config.sh                    # Shared configuration
└── build/
    ├── apply-patches.sh         # Patches FFmpeg for re-entrant usage
    ├── build-lame.sh            # Builds libmp3lame
    ├── build-ffmpeg.sh          # Builds FFmpeg
    └── create-xcframework.sh    # Creates XCFramework
```

---

## Usage Examples

### Basic Conversion

```swift
import SwiftFFmpeg

do {
    let (exitCode, output) = try SwiftFFmpeg.execute([
        "-i", inputPath,
        "-c", "copy",
        outputPath
    ])
    print("Conversion completed with exit code: \(exitCode)")
} catch SwiftFFmpegError.executionFailed(let code) {
    print("FFmpeg failed with code: \(code)")
}
```

### Get FFmpeg Version

```swift
// Using ffmpeg (default)
let (_, output) = try SwiftFFmpeg.execute(["-version"], tool: .ffmpeg)
print(output)

// Or simply (defaults to .ffmpeg)
let (_, version) = try SwiftFFmpeg.execute(["-version"])
print(version)
```

### Using ffprobe

```swift
// Get ffprobe version
let (_, version) = try SwiftFFmpeg.execute(["-version"], tool: .ffprobe)
print(version)

// Get media format information
let (_, formatInfo) = try SwiftFFmpeg.execute(
    ["-v", "error", "-show_format", "video.mp4"],
    tool: .ffprobe
)
print(formatInfo)

// Get stream information
let (_, streamInfo) = try SwiftFFmpeg.execute(
    ["-v", "error", "-show_streams", "-of", "json", "video.mp4"],
    tool: .ffprobe
)
print(streamInfo)

// Get media duration
let (_, durationStr) = try SwiftFFmpeg.execute(
    ["-v", "error", "-show_entries", "format=duration",
     "-of", "default=noprint_wrappers=1:nokey=1", "video.mp4"],
    tool: .ffprobe
)
if let duration = Double(durationStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
    print("Duration: \(duration) seconds")
}
```

### Extract Audio

```swift
let (exitCode, output) = try SwiftFFmpeg.execute([
    "-i", videoPath,
    "-vn",              // No video
    "-c:a", "libmp3lame",
    "-b:a", "192k",
    audioPath
])
```

### Merge Video + Audio

```swift
let (exitCode, output) = try SwiftFFmpeg.execute([
    "-i", videoPath,
    "-i", audioPath,
    "-c:v", "copy",
    "-c:a", "copy",
    outputPath
])
```

### With Logging

```swift
SwiftFFmpeg.setLogLevel(.info)
SwiftFFmpeg.setLogHandler { level, message in
    print("[\(level)] \(message)")
}

try SwiftFFmpeg.execute([...])

// Disable when done
SwiftFFmpeg.setLogHandler(nil)
```

---

## API Reference

| Method | Description |
|--------|-------------|
| `execute([String], tool: FFmpegTool)` | Run FFmpeg or ffprobe command and capture output. Returns `(exitCode, output)`. Defaults to `.ffmpeg`. Throws on non-zero exit. |
| `setLogLevel(FFmpegLogLevel)` | Set log verbosity: `.quiet`, `.error`, `.warning`, `.info`, `.debug` |
| `setLogHandler((level, message) -> Void)` | Receive FFmpeg log messages. Pass `nil` to disable. |

**FFmpegTool enum:**
- `.ffmpeg` - Use ffmpeg (default)
- `.ffprobe` - Use ffprobe

---

## Requirements

- iOS 13.0+
- Xcode 14+
- macOS (for building)

---

## Troubleshooting

**Build fails with "FFmpeg source not found"**
- The build script auto-downloads FFmpeg. Ensure you have internet access and `git` installed.

**"No such module 'SwiftFFmpeg'"**
- Make sure `FFmpeg.xcframework` exists (run the build script first)
- Check that the framework is added to your target

**App crashes on second FFmpeg call**
- This is fixed automatically. The build script patches FFmpeg for re-entrant usage.

---

## License

FFmpeg is licensed under LGPL/GPL. See [FFmpeg License](https://ffmpeg.org/legal.html).
