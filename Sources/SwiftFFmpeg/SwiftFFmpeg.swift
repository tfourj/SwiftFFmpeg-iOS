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

    /// Execute FFmpeg with the given arguments (just like the CLI).
    ///
    /// Example:
    /// ```swift
    /// try SwiftFFmpeg.execute([
    ///     "-i", inputPath,
    ///     "-vf", "scale=1280:-2",
    ///     "-c:v", "libx264",
    ///     "-c:a", "aac",
    ///     outputPath
    /// ])
    /// ```
    @discardableResult
    public static func execute(_ arguments: [String]) throws -> Int {
        // argv[0] must be some program name, conventionally "ffmpeg"
        let allArgs = ["ffmpeg"] + arguments

        // Convert [String] to [UnsafeMutablePointer<CChar>?]
        var cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) }
        
        // Copy for cleanup to avoid overlapping access
        let cArgsCopy = cArgs
        
        defer {
            // Free all allocated strings after execution completes
            for ptr in cArgsCopy {
                if let p = ptr {
                    free(p)
                }
            }
        }
        
        // Ensure the array stays in a stable memory location
        return try cArgs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw SwiftFFmpegError.executionFailed(code: -1)
            }
            
            let argc = Int32(allArgs.count)
            let exitCode = ffmpeg_execute(argc, baseAddress)
            let exitCodeInt = Int(exitCode)
            
            // Normalize exit code (FFmpeg typically returns 0 for success, 1 for error, or signal numbers)
            // If exit code is way out of bounds, treat it as a crash
            let normalizedExitCode: Int
            if exitCodeInt < -256 || exitCodeInt > 255 {
                // Likely a crash or memory corruption - normalize to -1
                normalizedExitCode = -1
            } else {
                normalizedExitCode = exitCodeInt
            }

            if normalizedExitCode != 0 {
                throw SwiftFFmpegError.executionFailed(code: normalizedExitCode)
            }

            return normalizedExitCode
        }
    }
    
    /// Execute FFmpeg and capture stdout/stderr output.
    /// Useful for commands like `-version` that print information.
    ///
    /// Example:
    /// ```swift
    /// let output = try SwiftFFmpeg.executeWithOutput(["-version"])
    /// print(output)
    /// ```
    ///
    /// - Parameter arguments: Array of FFmpeg arguments
    /// - Returns: Tuple containing exit code and output string
    /// - Throws: `SwiftFFmpegError.executionFailed(code:)` if FFmpeg returns non-zero exit code
    public static func executeWithOutput(_ arguments: [String]) throws -> (exitCode: Int, output: String) {
        // argv[0] must be some program name, conventionally "ffmpeg"
        let allArgs = ["ffmpeg"] + arguments

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
            let exitCode = ffmpeg_execute_with_output(argc, baseAddress, outputBuffer, bufferSize)
            let output = String(cString: outputBuffer)
            let exitCodeInt = Int(exitCode)

            if exitCodeInt != 0 {
                throw SwiftFFmpegError.executionFailed(code: exitCodeInt)
            }

            return (exitCodeInt, output)
        }
    }
    
    /// Execute ffprobe to get media information.
    /// Useful for getting duration, codec info, etc.
    ///
    /// Example:
    /// ```swift
    /// let duration = try SwiftFFmpeg.getDuration(from: videoURL)
    /// print("Duration: \(duration) seconds")
    /// ```
    ///
    /// - Parameter url: URL of the media file
    /// - Returns: Duration in seconds
    /// - Throws: `SwiftFFmpegError.executionFailed(code:)` if ffprobe fails
    public static func getDuration(from url: URL) throws -> Double {
        let arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        
        let allArgs = ["ffprobe"] + arguments
        
        // Convert [String] to [UnsafeMutablePointer<CChar>?]
        var cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) }
        let cArgsCopy = cArgs
        
        // Allocate buffer for output
        let bufferSize = 1024
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
            let exitCode = ffprobe_execute(argc, baseAddress, outputBuffer, bufferSize)
            let exitCodeInt = Int(exitCode)
            
            if exitCodeInt != 0 {
                throw SwiftFFmpegError.executionFailed(code: exitCodeInt)
            }
            
            // Parse duration from output
            let output = String(cString: outputBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let duration = Double(output), duration > 0 else {
                throw SwiftFFmpegError.executionFailed(code: -1)
            }
            
            return duration
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
