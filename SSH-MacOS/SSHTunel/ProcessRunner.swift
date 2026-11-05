//  ProcessRunner.swift
//
//  Helpers to run short-lived command-line tools (ssh -O, lsof, ps, umount…)
//  without ever blocking the main thread. Every call has a timeout, because
//  after a sleep/wake cycle some of these tools can block for a long time
//  (e.g. on a dead SMB mount that was served through the tunnel).

import Foundation
import Darwin

nonisolated struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

nonisolated private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ d: Data) {
        lock.lock()
        data = d
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

nonisolated enum ProcessRunner {
    /// Runs `body` on a background queue and resumes the caller with its result.
    static func background<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: body())
            }
        }
    }

    /// Async wrapper around `runBlocking`, safe to call from the main actor.
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 5) async -> ProcessResult {
        await background { runBlocking(exe, args, timeout: timeout) }
    }

    /// Runs a command synchronously on the *current* thread. Never call from the main thread.
    static func runBlocking(_ exe: String, _ args: [String], timeout: TimeInterval = 5) -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }

        do {
            try p.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: "\(error)", timedOut: false)
        }

        // Drain both pipes concurrently so a chatty child cannot fill the pipe
        // buffer and deadlock against waitUntilExit().
        let outBox = DataBox()
        let errBox = DataBox()
        let readers = DispatchGroup()
        for (pipe, box) in [(out, outBox), (err, errBox)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            let pid = p.processIdentifier
            p.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                // Escalate if SIGTERM was ignored. If the process already exited the
                // semaphore was signalled and this is a harmless no-op on a reaped pid.
                if exited.wait(timeout: .now()) == .timedOut {
                    kill(pid, SIGKILL)
                }
            }
            return ProcessResult(exitCode: -2, stdout: "", stderr: "timed out after \(Int(timeout))s", timedOut: true)
        }

        // A grandchild may still hold the pipes open; don't wait forever for EOF.
        _ = readers.wait(timeout: .now() + 1)

        return ProcessResult(
            exitCode: p.terminationStatus,
            stdout: String(data: outBox.get(), encoding: .utf8) ?? "",
            stderr: String(data: errBox.get(), encoding: .utf8) ?? "",
            timedOut: false
        )
    }
}
