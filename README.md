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

## License

FFmpeg is licensed under LGPL/GPL. See [FFmpeg License](https://ffmpeg.org/legal.html).
