import Foundation
import CFFmpegCLI

public enum SwiftFFmpegError: Error {
    case executionFailed(code: Int)
}

/// Log level (matches FFmpeg log integer levels)
public enum FFmpegLogLevel: Int32 {
    case quiet  = -8
    case panic  = 0
    case fatal  = 8
    case error  = 16
    case warning = 24
    case info   = 32
    case verbose = 40
    case debug  = 48
    case trace  = 56
}

/// Tool to use for execution
public enum FFmpegTool {
    case ffmpeg
    case ffprobe
}

/// Convenience wrapper for calling the FFmpeg CLI-style API from Swift.
public enum SwiftFFmpeg {
    public typealias LogHandler = (_ level: FFmpegLogLevel, _ message: String) -> Void

    // Stored log handler used by global C callback.
    private static var logHandler: LogHandler?

    /// Set a log handler that receives FFmpeg log lines.
    /// Call with `nil` to disable.
    public static func setLogHandler(_ handler: LogHandler?) {
        logHandler = handler

        if handler != nil {
            ffmpeg_set_swift_logger(ffmpeg_log_swift)
        } else {
            ffmpeg_set_swift_logger(nil)
        }
    }

    /// Set FFmpeg log level.
    public static func setLogLevel(_ level: FFmpegLogLevel) {
        ffmpeg_set_log_level(level.rawValue)
    }

    /// INTERNAL: called from the C bridge.
    static func handleLog(level: Int32, message: String) {
        guard let handler = logHandler else { return }
        let lvl = FFmpegLogLevel(rawValue: level) ?? .info
        handler(lvl, message)
    }

    /// Execute FFmpeg or ffprobe with the given arguments and capture stdout/stderr output.
    ///
    /// Example:
    /// ```swift
    /// // Using ffmpeg (default)
    /// let (exitCode, output) = try SwiftFFmpeg.execute([
    ///     "-i", inputPath,
    ///     "-vf", "scale=1280:-2",
    ///     "-c:v", "libx264",
    ///     "-c:a", "aac",
    ///     outputPath
    /// ])
    ///
    /// // Using ffprobe
    /// let (exitCode, probeOutput) = try SwiftFFmpeg.execute(
    ///     ["-v", "error", "-show_format", "video.mp4"],
    ///     tool: .ffprobe
    /// )
    ///
    /// // Get duration using ffprobe
    /// let (_, durationStr) = try SwiftFFmpeg.execute(
    ///     ["-v", "error", "-show_entries", "format=duration",
    ///      "-of", "default=noprint_wrappers=1:nokey=1", "video.mp4"],
    ///     tool: .ffprobe
    /// )
    /// let duration = Double(durationStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    /// ```
    ///
    /// - Parameters:
    ///   - arguments: Array of FFmpeg/ffprobe arguments
    ///   - tool: Tool to execute (`.ffmpeg` or `.ffprobe`). Defaults to `.ffmpeg`
    /// - Returns: Tuple containing exit code and output string
    /// - Throws: `SwiftFFmpegError.executionFailed(code:)` if the tool returns non-zero exit code
    public static func execute(_ arguments: [String], tool: FFmpegTool = .ffmpeg) throws -> (exitCode: Int, output: String) {
        // argv[0] must be some program name
        let programName = tool == .ffmpeg ? "ffmpeg" : "ffprobe"
        let allArgs = [programName] + arguments

        // Convert [String] to [UnsafeMutablePointer<CChar>?]
        var cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) }
        
        // Copy for cleanup to avoid overlapping access
        let cArgsCopy = cArgs
        
        // Allocate buffer for output (64KB should be enough for most commands)
        let bufferSize = 64 * 1024
        let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        
        defer {
            // Free all allocated strings
            for ptr in cArgsCopy {
                if let p = ptr {
                    free(p)
                }
            }
            outputBuffer.deallocate()
        }
        
        // Ensure the array stays in a stable memory location
        return try cArgs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                outputBuffer.deallocate()
                throw SwiftFFmpegError.executionFailed(code: -1)
            }
            
            let argc = Int32(allArgs.count)
            let exitCode: Int32
            
            // Call the appropriate C function based on tool
            if tool == .ffmpeg {
                exitCode = ffmpeg_execute_with_output(argc, baseAddress, outputBuffer, bufferSize)
            } else {
                exitCode = ffprobe_execute_with_output(argc, baseAddress, outputBuffer, bufferSize)
            }
            
            let output = String(cString: outputBuffer)
            let exitCodeInt = Int(exitCode)

            if exitCodeInt != 0 {
                throw SwiftFFmpegError.executionFailed(code: exitCodeInt)
            }

            return (exitCodeInt, output)
        }
    }
}

/// Global C-exposed function that C side will call.
/// DO NOT rename without updating C prototype.
@_cdecl("ffmpeg_log_swift")
func ffmpeg_log_swift(_ level: Int32, _ message: UnsafePointer<CChar>?) {
    guard let message = message else { return }
    let str = String(cString: message)
    SwiftFFmpeg.handleLog(level: level, message: str)
}
