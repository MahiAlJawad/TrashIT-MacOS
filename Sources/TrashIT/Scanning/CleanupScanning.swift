import Foundation

protocol CleanupScanning: Sendable {
    var id: String { get }
    func scan(settings: ScannerSettings) async -> ScanResult
}

struct ScanBudget: Sendable {
    let deadline: Date

    init(seconds: TimeInterval = 15) {
        deadline = Date().addingTimeInterval(seconds)
    }

    var isExpired: Bool { Date() >= deadline || Task.isCancelled }
}

struct ScanProgress: Sendable {
    let scannerID: String
    let result: ScanResult
    let completedScanners: Int
    let totalScanners: Int
}

actor StorageScanner {
    private let scanners: [any CleanupScanning]
    private let scanTimeoutNanoseconds: UInt64

    init(
        scanners: [any CleanupScanning] = StorageScanner.defaultScanners,
        scanTimeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        self.scanners = scanners
        self.scanTimeoutNanoseconds = scanTimeoutNanoseconds
    }

    private static var defaultScanners: [any CleanupScanning] {
        #if TRASHIT_APP_STORE
        // The sandboxed build only scans folders the user has explicitly selected.
        [ProjectArtifactScanner(), OldFileScanner()]
        #else
        [
            XcodeScanner(), SimulatorScanner(), DeveloperCacheScanner(), ProjectArtifactScanner(),
            DockerScanner(), OldFileScanner(), BrowserCacheScanner(), GeneralStorageScanner()
        ]
        #endif
    }

    func progressStream(settings: ScannerSettings) -> AsyncStream<ScanProgress> {
        let scanners = self.scanners
        let scanTimeoutNanoseconds = self.scanTimeoutNanoseconds
        return AsyncStream { continuation in
            let coordinator = ScanStreamCoordinator(
                continuation: continuation,
                totalScanners: scanners.count
            )
            let tasks = scanners.map { scanner in
                Task.detached(priority: .userInitiated) {
                    let result = await scanner.scan(settings: settings)
                    await coordinator.submit(scannerID: scanner.id, result: result)
                }
            }
            let timeoutTask = Task.detached {
                try? await Task.sleep(nanoseconds: scanTimeoutNanoseconds)
                guard !Task.isCancelled else { return }
                await coordinator.timeOut()
            }
            Task { await coordinator.install(tasks: tasks, timeoutTask: timeoutTask) }
            continuation.onTermination = { _ in
                Task { await coordinator.cancel() }
            }
        }
    }
}

private actor ScanStreamCoordinator {
    private let continuation: AsyncStream<ScanProgress>.Continuation
    private let totalScanners: Int
    private var completedScanners = 0
    private var finished = false
    private var tasks: [Task<Void, Never>] = []
    private var timeoutTask: Task<Void, Never>?

    init(continuation: AsyncStream<ScanProgress>.Continuation, totalScanners: Int) {
        self.continuation = continuation
        self.totalScanners = totalScanners
    }

    func install(tasks: [Task<Void, Never>], timeoutTask: Task<Void, Never>) {
        self.tasks = tasks
        self.timeoutTask = timeoutTask
        if finished {
            tasks.forEach { $0.cancel() }
            timeoutTask.cancel()
        }
    }

    func submit(scannerID: String, result: ScanResult) {
        guard !finished else { return }
        completedScanners += 1
        continuation.yield(ScanProgress(
            scannerID: scannerID,
            result: result,
            completedScanners: completedScanners,
            totalScanners: totalScanners
        ))
        if completedScanners == totalScanners { finish() }
    }

    func timeOut() {
        guard !finished else { return }
        continuation.yield(ScanProgress(
            scannerID: "scan-timeout",
            result: ScanResult(issues: [
                ScanIssue(
                    scanner: "scan",
                    message: "The overall scan reached its 30-second limit. Completed results are shown; try narrower scan folders for the remaining checks."
                )
            ]),
            completedScanners: completedScanners,
            totalScanners: totalScanners
        ))
        finish()
    }

    func cancel() {
        guard !finished else { return }
        finish()
    }

    private func finish() {
        finished = true
        tasks.forEach { $0.cancel() }
        timeoutTask?.cancel()
        continuation.finish()
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
