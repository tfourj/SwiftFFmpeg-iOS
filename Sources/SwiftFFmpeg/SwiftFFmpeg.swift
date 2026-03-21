import Foundation
internal import CFFmpegCLI

public enum SwiftFFmpegError: Error {
    case executionFailed(code: Int, stdout: String, stderr: String)
}

public struct FFmpegExecutionResult {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
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

    private static let logHandlerLock = NSLock()
    private static let logDispatchQueue = DispatchQueue(label: "com.tfourj.swiftffmpeg.log-handler")
    private static var logHandler: LogHandler?

    /// Set a log handler that receives FFmpeg log lines.
    /// Call with `nil` to disable.
    public static func setLogHandler(_ handler: LogHandler?) {
        logHandlerLock.lock()
        logHandler = handler
        logHandlerLock.unlock()

        ffmpeg_set_swift_logger(ffmpeg_log_swift)
    }

    /// Set FFmpeg log level.
    public static func setLogLevel(_ level: FFmpegLogLevel) {
        ffmpeg_set_log_level(level.rawValue)
    }

    /// Request cancellation of the active ffmpeg or ffprobe execution.
    public static func requestCancel() {
        ffmpeg_request_cancel()
    }

    static func handleLog(level: Int32, message: String) {
        logHandlerLock.lock()
        let handler = logHandler
        logHandlerLock.unlock()
        guard let handler else { return }
        let lvl = FFmpegLogLevel(rawValue: level) ?? .info
        logDispatchQueue.async {
            handler(lvl, message)
        }
    }

    /// Execute FFmpeg or ffprobe and return stdout only.
    /// Stderr is still available through `executeDetailed` and through thrown errors.
    public static func execute(_ arguments: [String], tool: FFmpegTool = .ffmpeg) throws -> (exitCode: Int, output: String) {
        let result = try executeDetailed(arguments, tool: tool)
        return (result.exitCode, result.stdout)
    }

    /// Execute FFmpeg or ffprobe with separate stdout and stderr capture.
    public static func executeDetailed(_ arguments: [String], tool: FFmpegTool = .ffmpeg) throws -> FFmpegExecutionResult {
        ffmpeg_clear_cancel()

        let programName = tool == .ffmpeg ? "ffmpeg" : "ffprobe"
        let allArgs = [programName] + arguments
        var cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) }
        let cArgsCopy = cArgs

        let bufferSize = 64 * 1024
        let stdoutBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        let stderrBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)

        defer {
            for ptr in cArgsCopy {
                if let p = ptr {
                    free(p)
                }
            }
            stdoutBuffer.deallocate()
            stderrBuffer.deallocate()
        }

        return try cArgs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw SwiftFFmpegError.executionFailed(code: -1, stdout: "", stderr: "")
            }

            let argc = Int32(allArgs.count)
            let exitCode: Int32

            if tool == .ffmpeg {
                exitCode = ffmpeg_execute_with_output(
                    argc,
                    baseAddress,
                    stdoutBuffer,
                    bufferSize,
                    stderrBuffer,
                    bufferSize
                )
            } else {
                exitCode = ffprobe_execute_with_output(
                    argc,
                    baseAddress,
                    stdoutBuffer,
                    bufferSize,
                    stderrBuffer,
                    bufferSize
                )
            }

            let stdout = String(cString: stdoutBuffer)
            let stderr = String(cString: stderrBuffer)
            let exitCodeInt = Int(exitCode)

            if exitCodeInt != 0 {
                throw SwiftFFmpegError.executionFailed(code: exitCodeInt, stdout: stdout, stderr: stderr)
            }

            return FFmpegExecutionResult(exitCode: exitCodeInt, stdout: stdout, stderr: stderr)
        }
    }
}

@_cdecl("ffmpeg_log_swift")
func ffmpeg_log_swift(_ level: Int32, _ message: UnsafePointer<CChar>?) {
    guard let message = message else { return }
    let str = String(decoding: Data(bytes: message, count: strlen(message)), as: UTF8.self)
    SwiftFFmpeg.handleLog(level: level, message: str)
}
