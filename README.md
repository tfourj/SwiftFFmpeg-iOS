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

## Usage

Usage examples and API notes are in [USAGE.md](USAGE.md).

## Requirements

- iOS 13.0+
- Xcode 14+
- macOS for local builds
- CMake and pkg-config (`brew install cmake pkgconf`)

## Codec Build Scripts

`Scripts/build/build-libvpx.sh` builds libvpx 1.15.2 for VP8/VP9, and
`Scripts/build/build-opus.sh` builds Opus 1.5.2. Both download checksum-verified
sources and install separate static libraries for `iphoneos arm64` and
`iphonesimulator arm64` under `install/`. They can also be run individually.

## License

FFmpeg is licensed under LGPL/GPL. See [FFmpeg License](https://ffmpeg.org/legal.html).
