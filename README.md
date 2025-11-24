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

// Run any FFmpeg command
try SwiftFFmpeg.execute([
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
    try SwiftFFmpeg.execute([
        "-i", inputPath,
        "-c", "copy",
        outputPath
    ])
} catch SwiftFFmpegError.executionFailed(let code) {
    print("FFmpeg failed with code: \(code)")
}
```

### Get FFmpeg Version

```swift
let (_, output) = try SwiftFFmpeg.executeWithOutput(["-version"])
print(output)
```

### Extract Audio

```swift
try SwiftFFmpeg.execute([
    "-i", videoPath,
    "-vn",              // No video
    "-c:a", "libmp3lame",
    "-b:a", "192k",
    audioPath
])
```

### Merge Video + Audio

```swift
try SwiftFFmpeg.execute([
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
| `execute([String])` | Run FFmpeg command. Throws on non-zero exit. |
| `executeWithOutput([String])` | Run FFmpeg and capture output. Returns `(exitCode, output)`. |
| `setLogLevel(FFmpegLogLevel)` | Set log verbosity: `.quiet`, `.error`, `.warning`, `.info`, `.debug` |
| `setLogHandler((level, message) -> Void)` | Receive FFmpeg log messages. Pass `nil` to disable. |
| `getDuration(from: URL)` | Get media duration in seconds using ffprobe. |

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
