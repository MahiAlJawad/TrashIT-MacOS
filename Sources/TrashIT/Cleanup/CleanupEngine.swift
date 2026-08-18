import Foundation
import AppKit
import CryptoKit

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
                try revalidate(item)
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

        case .cleanToolCache(let kind):
            guard let executable = ToolLocator.executable(named: kind.executableName) else {
                throw CleanupExecutionError.commandFailed("\(kind.executableName) is unavailable.")
            }
            let output = try ProcessRunner.run(
                executable,
                arguments: kind.arguments,
                timeout: 120
            )
            guard output.status == 0 else {
                throw CleanupExecutionError.commandFailed(output.stderr)
            }
            return "Cleaned with \(kind.executableName)"
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

    private func revalidate(_ item: CleanupItem) throws {
        if let url = item.url {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CleanupExecutionError.stateChanged("The item no longer exists at its scanned location.")
            }
            if let relativeLeaf = item.metadata["validatedLeaf"] {
                let expected = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(relativeLeaf, isDirectory: true)
                    .standardizedFileURL
                guard expected == url.standardizedFileURL else {
                    throw CleanupExecutionError.stateChanged("The cache path no longer matches its validated owner location.")
                }
            }
        }

        if let duplicate = item.duplicateEvidence, let copy = item.url {
            guard FileManager.default.fileExists(atPath: duplicate.keeperURL.path),
                  !FileInspection.isSymbolicLink(duplicate.keeperURL),
                  fileSize(copy) == fileSize(duplicate.keeperURL),
                  let copyDigest = digest(copy),
                  let keeperDigest = digest(duplicate.keeperURL),
                  copyDigest == keeperDigest else {
                throw CleanupExecutionError.stateChanged("The duplicate or its kept original changed after the scan.")
            }
        }

        switch item.action {
        case .deleteSimulatorDevice(let udid):
            try revalidateSimulatorDevice(udid)
        case .deleteSimulatorRuntime:
            if item.recommendations.contains(.outdatedSimulator) {
                try revalidateOutdatedRuntime(item)
            }
        default:
            break
        }
    }

    private func revalidateSimulatorDevice(_ udid: String) throws {
        struct Device: Decodable { let udid: String; let state: String? }
        struct Payload: Decodable { let devices: [String: [Device]] }
        let output = try ProcessRunner.runSimctl(arguments: ["list", "devices", "-j"])
        guard output.status == 0,
              let payload = try? JSONDecoder().decode(Payload.self, from: output.stdout),
              let current = payload.devices.values.flatMap({ $0 }).first(where: { $0.udid == udid }) else {
            throw CleanupExecutionError.stateChanged("The simulator device inventory changed. Scan again.")
        }
        guard current.state?.lowercased() != "booted" else {
            throw CleanupExecutionError.stateChanged("The simulator is now booted and was not deleted.")
        }
    }

    private func revalidateOutdatedRuntime(_ item: CleanupItem) throws {
        let devicesOutput = try ProcessRunner.runSimctl(arguments: ["list", "-j"])
        struct Device: Decodable { let state: String? }
        struct DevicePayload: Decodable { let devices: [String: [Device]]? }
        let devices = try? JSONDecoder().decode(DevicePayload.self, from: devicesOutput.stdout)
        let inUse = Set((devices?.devices ?? [:]).compactMap { key, entries in
            entries.contains(where: { $0.state?.lowercased() == "booted" }) ? key : nil
        })

        let output = try ProcessRunner.runSimctl(arguments: ["runtime", "list", "-v", "-j"])
        guard output.status == 0,
              let images = try? JSONDecoder().decode([String: SimulatorScanner.RuntimeImage].self, from: output.stdout) else {
            throw CleanupExecutionError.stateChanged("The simulator runtime inventory could not be revalidated.")
        }
        let refreshed = SimulatorScanner().runtimeItems(
            Array(images.values), inUseRuntimeIdentifiers: inUse, budget: ScanBudget(seconds: 5)
        )
        let identifier = item.metadata["identifier"]
        guard let current = refreshed.first(where: { $0.metadata["identifier"] == identifier }),
              current.recommendations.contains(.outdatedSimulator) else {
            throw CleanupExecutionError.stateChanged("This runtime is no longer an older safe recommendation. Scan again.")
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
    }

    private func digest(_ url: URL) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize()
        } catch {
            return nil
        }
    }

    private func rejectRunningApplication(for item: CleanupItem) throws {
        if item.category == .xcode,
           let xcode = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" }) {
            throw SafetyPolicyError.applicationRunning(xcode.localizedName ?? "Xcode")
        }

        if item.category == .appCaches,
           let identifier = item.metadata["bundleCandidate"],
           let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == identifier }) {
            throw SafetyPolicyError.applicationRunning(running.localizedName ?? identifier)
        }

        if let processNames = item.metadata["blockingProcesses"]?.split(separator: ",").map(String.init) {
            for processName in processNames where ToolLocator.isProcessRunning(named: processName) {
                throw SafetyPolicyError.applicationRunning(processName)
            }
        }
    }
}

enum CleanupExecutionError: LocalizedError {
    case commandFailed(String)
    case trashFailed
    case runtimeInventoryChanged
    case stateChanged(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output): output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "The system command failed." : output
        case .trashFailed: "Finder did not move the item to Trash."
        case .runtimeInventoryChanged: "This runtime image is no longer installed. Scan again to refresh the runtime list."
        case .stateChanged(let reason): reason
        }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
