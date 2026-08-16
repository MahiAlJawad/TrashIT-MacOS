import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String
}

enum ProcessRunnerError: LocalizedError {
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let command): "\(command) did not respond within the scan time limit."
        }
    }
}

enum ProcessRunner {
    static func run(
        _ executable: URL,
        arguments: [String],
        timeout: TimeInterval = 12
    ) throws -> ProcessOutput {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let completion = DispatchSemaphore(value: 0)
        let readers = DispatchGroup()
        let dataLock = NSLock()
        var stdout = Data()
        var stderr = Data()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { _ in completion.signal() }

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            dataLock.withLock { stdout = data }
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            dataLock.withLock { stderr = data }
            readers.leave()
        }

        try process.run()
        if completion.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 2)
            if process.isRunning { process.interrupt() }
            output.fileHandleForReading.closeFile()
            error.fileHandleForReading.closeFile()
            throw ProcessRunnerError.timedOut(executable.lastPathComponent)
        }
        readers.wait()

        return ProcessOutput(
            status: process.terminationStatus,
            stdout: dataLock.withLock { stdout },
            stderr: dataLock.withLock { String(data: stderr, encoding: .utf8) ?? "" }
        )
    }

    static func runSimctl(arguments: [String], timeout: TimeInterval = 12) throws -> ProcessOutput {
        if let simctl = ToolLocator.simctl {
            return try run(simctl, arguments: arguments, timeout: timeout)
        }
        return try run(
            URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl"] + arguments,
            timeout: timeout
        )
    }
}

enum ToolLocator {
    static var simctl: URL? {
        firstExecutable(at: [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl",
            "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl"
        ])
    }

    static var docker: URL? {
        firstExecutable(at: [
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker"
        ])
    }

    private static func firstExecutable(at paths: [String]) -> URL? {
        paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }
}
