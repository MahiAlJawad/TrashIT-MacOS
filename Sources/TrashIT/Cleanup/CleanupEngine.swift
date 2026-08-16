import Foundation
import AppKit

actor CleanupEngine {
    private let receiptStore: ReceiptStore

    init(receiptStore: ReceiptStore) {
        self.receiptStore = receiptStore
    }

    func clean(_ items: [CleanupItem]) async -> CleanupReceipt {
        let startedAt = Date()
        var entries: [CleanupReceipt.Entry] = []

        for item in items {
            do {
                try SafetyPolicy.validate(item)
                try rejectRunningApplication(for: item)
                let message = try await execute(item)
                entries.append(CleanupReceipt.Entry(
                    id: UUID(),
                    itemName: item.name,
                    originalPath: item.url?.path,
                    bytes: item.allocatedBytes,
                    action: item.action,
                    succeeded: true,
                    message: message
                ))
            } catch {
                entries.append(CleanupReceipt.Entry(
                    id: UUID(),
                    itemName: item.name,
                    originalPath: item.url?.path,
                    bytes: item.allocatedBytes,
                    action: item.action,
                    succeeded: false,
                    message: error.localizedDescription
                ))
            }
        }

        let receipt = CleanupReceipt(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: Date(),
            entries: entries
        )
        try? await receiptStore.save(receipt)
        return receipt
    }

    private func execute(_ item: CleanupItem) async throws -> String {
        switch item.action {
        case .deleteRegeneratable:
            guard let url = item.url else { throw SafetyPolicyError.missingURL }
            try await recycle(url)
            return "Moved to Bin"

        case .deletePermanently:
            guard let url = item.url else { throw SafetyPolicyError.missingURL }
            try FileManager.default.removeItem(at: url)
            return "Deleted permanently from Bin"

        case .moveToTrash:
            guard let url = item.url else { throw SafetyPolicyError.missingURL }
            try await recycle(url)
            return "Moved to Bin"

        case .evictCloudCopy:
            guard let url = item.url else { throw SafetyPolicyError.missingURL }
            try FileManager.default.evictUbiquitousItem(at: url)
            return "Removed local copy; cloud copy retained"

        case .deleteSimulatorDevice(let udid):
            let output = try ProcessRunner.runSimctl(arguments: ["delete", udid], timeout: 120)
            guard output.status == 0 else {
                throw CleanupExecutionError.commandFailed(output.stderr)
            }
            return "Deleted simulator device"

        case .deleteSimulatorRuntime(let identifier):
            let output = try ProcessRunner.runSimctl(arguments: ["runtime", "delete", identifier], timeout: 120)
            guard output.status == 0 else {
                if output.stderr.localizedCaseInsensitiveContains("No matching images")
                    || output.stderr.localizedCaseInsensitiveContains("No runtime disk images") {
                    throw CleanupExecutionError.runtimeInventoryChanged
                }
                throw CleanupExecutionError.commandFailed(output.stderr)
            }
            return "Uninstalled simulator runtime"

        case .pruneDocker:
            guard let docker = ToolLocator.docker else {
                throw CleanupExecutionError.commandFailed("Docker’s command-line tool is unavailable.")
            }
            let output = try ProcessRunner.run(
                docker,
                arguments: ["system", "prune", "--all", "--force"],
                timeout: 120
            )
            guard output.status == 0 else {
                throw CleanupExecutionError.commandFailed(output.stderr)
            }
            return "Pruned stopped containers, unused images, networks, and build cache; volumes were retained"
        }
    }

    private func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { moved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if moved[url] == nil {
                    continuation.resume(throwing: CleanupExecutionError.trashFailed)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func rejectRunningApplication(for item: CleanupItem) throws {
        if item.category == .xcode,
           let xcode = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" }) {
            throw SafetyPolicyError.applicationRunning(xcode.localizedName ?? "Xcode")
        }
        guard item.category == .appCaches,
              let identifier = item.metadata["bundleCandidate"] else { return }
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == identifier }
        if let running {
            throw SafetyPolicyError.applicationRunning(running.localizedName ?? identifier)
        }
    }
}

enum CleanupExecutionError: LocalizedError {
    case commandFailed(String)
    case trashFailed
    case runtimeInventoryChanged

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output): output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "The system command failed." : output
        case .trashFailed: "Finder did not move the item to Trash."
        case .runtimeInventoryChanged: "This runtime image is no longer installed. Scan again to refresh the runtime list."
        }
    }
}
