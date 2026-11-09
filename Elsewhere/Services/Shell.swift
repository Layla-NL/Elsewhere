import Foundation

/// 一次命令行调用的结果。
struct CommandResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    var timedOut = false

    var ok: Bool { status == 0 && !timedOut }

    /// 给用户看的原始输出：stderr 在前，stdout 在后。
    var output: String {
        var parts = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if timedOut { parts.append("（命令超时，已终止）") }
        if parts.isEmpty { return "退出码 \(status)，没有输出。" }
        return parts.joined(separator: "\n")
    }
}

/// 用 `Process` 跑外部命令。App 没有沙盒，所以可以直接调用 `xcrun`。
enum Shell {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(executable, arguments, timeout: timeout))
            }
        }
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    private static func runSync(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: "无法启动 \(executable)：\(error.localizedDescription)")
        }

        // 两个管道分别在后台读完，避免某一边写满缓冲区导致死锁。
        let out = Buffer(), err = Buffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            out.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            err.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        var timedOut = false
        if group.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = group.wait(timeout: .now() + 3)
        }
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: out.data, as: UTF8.self),
            stderr: String(decoding: err.data, as: UTF8.self),
            timedOut: timedOut
        )
    }
}
