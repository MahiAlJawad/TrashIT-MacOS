import Darwin
import Foundation
import TrashITCore

private enum CLIError: LocalizedError {
    case missingValue(String)
    case invalidOption(String)
    case invalidNumber(String)
    case missingSelection

    var errorDescription: String? {
        switch self {
        case .missingValue(let option): "Missing value after \(option)."
        case .invalidOption(let option): "Unknown option: \(option)"
        case .invalidNumber(let value): "Invalid number or byte size: \(value)"
        case .missingSelection: "clean requires --select safe, simulators, or duplicates."
        }
    }
}

private struct CommandOptions {
    var configuration = TrashITCLIConfiguration()
    var selection: TrashITCLISelection?
    var json = false
    var confirmed = false
}

private enum TrashITCommand {
    static func run(_ arguments: [String]) async throws -> Int {
        guard let command = arguments.first else {
            printHelp()
            return 0
        }

        switch command {
        case "--version", "-v", "version":
            print("trashit \(TrashITCoreInfo.version)")
            return 0
        case "help", "--help", "-h":
            printHelp()
            return 0
        case "scan", "list":
            let options = try parse(Array(arguments.dropFirst()), permitsConfirmation: false)
            writeProgress("Scanning with TrashITCore…", json: options.json)
            let report = await TrashITCLIService().scan(
                configuration: options.configuration,
                selection: options.selection
            )
            try printScan(report, json: options.json)
            return 0
        case "clean":
            let options = try parse(Array(arguments.dropFirst()), permitsConfirmation: true)
            guard let selection = options.selection else { throw CLIError.missingSelection }
            if !options.confirmed {
                writeProgress("Preparing cleanup preview…", json: options.json)
                let preview = await TrashITCLIService().scan(
                    configuration: options.configuration,
                    selection: selection
                )
                try printScan(preview, json: options.json)
                writeError("Preview only. Review the selected paths, then repeat with --yes to clean them.")
                return 2
            }
            writeProgress("Scanning again and revalidating before cleanup…", json: options.json)
            let report = await TrashITCLIService().clean(
                configuration: options.configuration,
                selection: selection
            )
            try printCleanup(report, json: options.json)
            return report.failureCount == 0 ? 0 : 1
        case "history":
            let options = try parse(Array(arguments.dropFirst()), permitsConfirmation: false, historyOnly: true)
            let history = await TrashITCLIService().history()
            try printHistory(history, json: options.json)
            return 0
        default:
            throw CLIError.invalidOption(command)
        }
    }

    private static func parse(
        _ arguments: [String],
        permitsConfirmation: Bool,
        historyOnly: Bool = false
    ) throws -> CommandOptions {
        var options = CommandOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json":
                options.json = true
            case "--yes", "-y":
                guard permitsConfirmation else { throw CLIError.invalidOption(argument) }
                options.confirmed = true
            case "--path", "-p":
                guard !historyOnly else { throw CLIError.invalidOption(argument) }
                options.configuration.paths.append(try value(after: argument, arguments: arguments, index: &index))
            case "--exclude" where !historyOnly:
                options.configuration.excludedPaths.append(try value(after: argument, arguments: arguments, index: &index))
            case "--select", "-s":
                guard !historyOnly else { throw CLIError.invalidOption(argument) }
                let rawValue = try value(after: argument, arguments: arguments, index: &index)
                guard let selection = parseSelection(rawValue) else { throw CLIError.invalidOption(rawValue) }
                options.selection = selection
            case "--old-days" where !historyOnly:
                let rawValue = try value(after: argument, arguments: arguments, index: &index)
                guard let days = Int(rawValue), days > 0 else { throw CLIError.invalidNumber(rawValue) }
                options.configuration.oldFileDays = days
            case "--minimum-file-size" where !historyOnly:
                let rawValue = try value(after: argument, arguments: arguments, index: &index)
                options.configuration.minimumLargeFileBytes = try parseBytes(rawValue)
            case "--minimum-cache-size" where !historyOnly:
                let rawValue = try value(after: argument, arguments: arguments, index: &index)
                options.configuration.minimumCacheBytes = try parseBytes(rawValue)
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                if !historyOnly && !argument.hasPrefix("-") {
                    options.configuration.paths.append(argument)
                } else {
                    throw CLIError.invalidOption(argument)
                }
            }
            index += 1
        }
        return options
    }

    private static func value(after option: String, arguments: [String], index: inout Int) throws -> String {
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue(option) }
        return arguments[index]
    }

    private static func parseSelection(_ value: String) -> TrashITCLISelection? {
        switch value.lowercased() {
        case "safe", "safe-cleanup": .safe
        case "simulators", "older-simulators": .simulators
        case "duplicates", "duplicate-copies": .duplicates
        default: nil
        }
    }

    private static func parseBytes(_ value: String) throws -> Int64 {
        let normalized = value.replacingOccurrences(of: "_", with: "").uppercased()
        let units: [(String, Double)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1_024),
            ("B", 1)
        ]
        for (suffix, multiplier) in units where normalized.hasSuffix(suffix) {
            let number = String(normalized.dropLast(suffix.count))
            guard let amount = Double(number), amount >= 0, amount * multiplier <= Double(Int64.max) else {
                throw CLIError.invalidNumber(value)
            }
            return Int64(amount * multiplier)
        }
        guard let bytes = Int64(normalized), bytes >= 0 else { throw CLIError.invalidNumber(value) }
        return bytes
    }

    private static func printScan(_ report: TrashITCLIScanReport, json: Bool) throws {
        if json {
            try printJSON(report)
            return
        }
        print("Found \(report.items.count) items using \(format(report.totalBytes)).")
        if let selection = report.selection {
            print("\(selection.title): \(report.selectedCount) items, \(format(report.selectedBytes)).")
        }
        for item in report.items {
            let marker = item.selected ? "*" : "-"
            print("\(marker) [\(item.categoryTitle)] \(format(item.allocatedBytes))  \(item.name)")
            if let path = item.path { print("    \(path)") }
            if let keeper = item.keeperPath { print("    keeps: \(keeper)") }
        }
        if !report.issues.isEmpty {
            print("\nScan notices:")
            report.issues.forEach { print("- [\($0.scanner)] \($0.message)") }
        }
    }

    private static func printCleanup(_ report: TrashITCLICleanupReport, json: Bool) throws {
        if json {
            try printJSON(report)
            return
        }
        print("\(report.selection.title): cleaned \(report.successCount) items (\(format(report.processedBytes))); \(report.failureCount) failed.")
        for entry in report.entries {
            print("\(entry.succeeded ? "✓" : "✗") \(entry.name): \(entry.message)")
            if let path = entry.originalPath { print("    \(path)") }
        }
        print("Receipt: \(report.receiptID.uuidString)")
    }

    private static func printHistory(_ history: [TrashITCLIHistoryEntry], json: Bool) throws {
        if json {
            try printJSON(history)
            return
        }
        guard !history.isEmpty else {
            print("No cleanup receipts yet.")
            return
        }
        let formatter = ISO8601DateFormatter()
        for entry in history {
            print("\(formatter.string(from: entry.finishedAt))  \(format(entry.processedBytes))  \(entry.successCount) succeeded, \(entry.failureCount) failed  \(entry.receiptID.uuidString)")
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func writeProgress(_ message: String, json: Bool) {
        if !json { writeError(message) }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func printHelp() {
        print("""
        trashit \(TrashITCoreInfo.version) — free GPL command-line frontend for TrashITCore

        Usage:
          trashit scan [PATH ...] [options]
          trashit clean --select RULE [PATH ...] [options]
          trashit history [--json]
          trashit --version

        Selection rules:
          safe          Regenerable and re-downloadable low-risk recommendations
          simulators    Older runtimes while retaining the newest release per OS major
          duplicates    Verified same-folder copies whose original is retained

        Options:
          -p, --path PATH              Add a project/old-file scan root (repeatable)
              --exclude PATH           Never suggest this path or its descendants
          -s, --select RULE            Mark a Smart Selection in scan; required by clean
              --old-days DAYS          Old-file threshold (default: 180)
              --minimum-file-size SIZE Minimum old-file size (default: 250MB)
              --minimum-cache-size SIZE Minimum cache/artifact size (default: 100MB)
              --json                   Emit machine-readable JSON
          -y, --yes                    Execute a clean after previewing without this flag

        Safety:
          A scan selects nothing unless --select is supplied. A clean accepts only a typed
          Smart Selection, requires --yes, rescans, revalidates state, and writes a receipt.
          Ordinary files move to Bin. Without PATH, Downloads is the old-file scan root.
          PATH adds project/old-file roots; known direct-edition scanners still run globally.
        """)
    }
}

do {
    let status = try await TrashITCommand.run(Array(CommandLine.arguments.dropFirst()))
    exit(Int32(status))
} catch {
    FileHandle.standardError.write(Data(("error: \(error.localizedDescription)\nRun 'trashit help' for usage.\n").utf8))
    exit(64)
}
// SPDX-License-Identifier: GPL-3.0-or-later
