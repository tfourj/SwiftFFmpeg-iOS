# SwiftFFmpeg-iOS

Swift package wrapper around FFmpeg for iOS.

## Add the Package

Choose one of these setup paths:

### Option 1: Download from Releases

1. Download `SwiftFFmpeg-iOS.zip` from the [GitHub release](https://github.com/tfourj/SwiftFFmpeg-iOS/releases).
2. Extract the archive.
3. In Xcode, open **File -> Add Package Dependencies...**
4. Click **Add Local...**
5. Select the extracted `SwiftFFmpeg-iOS` folder.

The release package already includes:

- `Package.swift`
- `Sources/`
- `FFmpeg.xcframework`
- `Licenses/` with libvpx and Opus license notices

Use this option if you want to add the package without building FFmpeg locally.

### Option 2: Clone and Build Locally

1. Clone the repository:

```bash
git clone https://github.com/tfourj/SwiftFFmpeg-iOS.git
cd SwiftFFmpeg-iOS
```

2. Build the local `FFmpeg.xcframework`:

```bash
./Scripts/build-ffmpeg-ios.sh --version 8.1
```

Use `--version latest` to build the newest tagged FFmpeg release. Use `--version git` only if you explicitly want a git snapshot, which may report a commit-style version string in `ffmpeg --version`.

3. In Xcode, open **File -> Add Package Dependencies...**
4. Click **Add Local...**
5. Select your local `SwiftFFmpeg-iOS` checkout.

Use this option if you want to build FFmpeg yourself or work on the package locally.

The full build includes LAME, libvpx, and Opus before building FFmpeg and packaging
both arm64 platforms. Use `--codecs-only` to rebuild just those dependencies;
`--ffmpeg-only` requires their installed libraries for both platforms.

The resulting framework supports WebM encoding with `libvpx` (VP8),
`libvpx-vp9` (VP9), and `libopus` (audio). For example, pass these arguments to
`SwiftFFmpeg.executeDetailed`:

```swift
["-i", inputPath, "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0",
 "-c:a", "libopus", "-b:a", "128k", outputWebMPath]
```

## Usage

Usage examples and API notes are in [USAGE.md](USAGE.md).

## Requirements

- iOS 13.0+
- Xcode 14+
- macOS for local builds
- CMake and pkg-config (`brew install cmake pkgconf`)

## Codec Build Scripts

`Scripts/build/patch-cancellation.py` connects FFmpeg's scheduler and I/O
interrupt callback to the wrapper's atomic cancellation flag. It runs from
`apply-patches.sh`, including on previously patched source trees. Rebuild the
XCFramework and distribute it with the updated wrapper to activate this fix.
Cancellation is checked every 20 ms between scheduler waits; an encoder already
working on a frame must return before its worker can stop safely.
Cancelled encoding skips queued frames and the final encoder flush, rather than
draining the encoder's lookahead buffer before returning to the app.

`Scripts/build/build-libvpx.sh` builds libvpx 1.15.2 for VP8/VP9, and
`Scripts/build/build-opus.sh` builds Opus 1.5.2. Both download checksum-verified
sources and install separate static libraries for `iphoneos arm64` and
`iphonesimulator arm64` under `install/`. They can also be run individually.

## License

FFmpeg is licensed under LGPL/GPL. See [FFmpeg License](https://ffmpeg.org/legal.html).
