import Foundation

public enum TrashITCLISelection: String, CaseIterable, Codable, Sendable {
    case safe
    case simulators
    case duplicates

    public var title: String {
        switch self {
        case .safe: "Safe cleanup"
        case .simulators: "Older simulator runtimes"
        case .duplicates: "Duplicate copies"
        }
    }

    fileprivate var recommendation: CleanupRecommendation {
        switch self {
        case .safe: .lowRisk
        case .simulators: .outdatedSimulator
        case .duplicates: .verifiedDuplicate
        }
    }
}

public struct TrashITCLIConfiguration: Sendable {
    public var paths: [String]
    public var excludedPaths: [String]
    public var oldFileDays: Int
    public var minimumLargeFileBytes: Int64
    public var minimumCacheBytes: Int64

    public init(
        paths: [String] = [],
        excludedPaths: [String] = [],
        oldFileDays: Int = 180,
        minimumLargeFileBytes: Int64 = 250 * 1_024 * 1_024,
        minimumCacheBytes: Int64 = 100 * 1_024 * 1_024
    ) {
        self.paths = paths
        self.excludedPaths = excludedPaths
        self.oldFileDays = oldFileDays
        self.minimumLargeFileBytes = minimumLargeFileBytes
        self.minimumCacheBytes = minimumCacheBytes
    }
}

public struct TrashITCLIItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String?
    public let category: String
    public let categoryTitle: String
    public let safety: String
    public let action: String
    public let allocatedBytes: Int64
    public let reason: String
    public let consequence: String
    public let recommendations: [String]
    public let selected: Bool
    public let keeperPath: String?
}

public struct TrashITCLIIssue: Codable, Sendable {
    public let scanner: String
    public let message: String
}

public struct TrashITCLIScanReport: Codable, Sendable {
    public let scannedAt: Date
    public let selection: TrashITCLISelection?
    public let totalBytes: Int64
    public let selectedCount: Int
    public let selectedBytes: Int64
    public let items: [TrashITCLIItem]
    public let issues: [TrashITCLIIssue]
}

public struct TrashITCLICleanupEntry: Codable, Sendable {
    public let name: String
    public let originalPath: String?
    public let bytes: Int64
    public let succeeded: Bool
    public let message: String
}

public struct TrashITCLICleanupReport: Codable, Sendable {
    public let receiptID: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let selection: TrashITCLISelection
    public let processedBytes: Int64
    public let successCount: Int
    public let failureCount: Int
    public let entries: [TrashITCLICleanupEntry]
}

public struct TrashITCLIHistoryEntry: Codable, Sendable {
    public let receiptID: UUID
    public let finishedAt: Date
    public let processedBytes: Int64
    public let successCount: Int
    public let failureCount: Int
}

public actor TrashITCLIService {
    private let scanner: StorageScanner
    private let receiptStore: ReceiptStore
    private let cleanupEngine: CleanupEngine

    public init() {
        let receiptStore = ReceiptStore()
        self.scanner = StorageScanner()
        self.receiptStore = receiptStore
        self.cleanupEngine = CleanupEngine(receiptStore: receiptStore)
    }

    init(scanner: StorageScanner, receiptStore: ReceiptStore) {
        self.scanner = scanner
        self.receiptStore = receiptStore
        self.cleanupEngine = CleanupEngine(receiptStore: receiptStore)
    }

    public func scan(
        configuration: TrashITCLIConfiguration = .init(),
        selection: TrashITCLISelection? = nil
    ) async -> TrashITCLIScanReport {
        let scan = await scanItems(configuration: configuration)
        return makeScanReport(items: scan.items, issues: scan.issues, selection: selection)
    }

    public func clean(
        configuration: TrashITCLIConfiguration = .init(),
        selection: TrashITCLISelection
    ) async -> TrashITCLICleanupReport {
        let scan = await scanItems(configuration: configuration)
        let candidates = scan.items.filter { $0.recommendations.contains(selection.recommendation) }
        let receipt = await cleanupEngine.clean(candidates)
        let entries = receipt.entries.map {
            TrashITCLICleanupEntry(
                name: $0.itemName,
                originalPath: $0.originalPath,
                bytes: $0.bytes,
                succeeded: $0.succeeded,
                message: $0.message
            )
        }
        return TrashITCLICleanupReport(
            receiptID: receipt.id,
            startedAt: receipt.startedAt,
            finishedAt: receipt.finishedAt,
            selection: selection,
            processedBytes: receipt.processedBytes,
            successCount: entries.filter(\.succeeded).count,
            failureCount: entries.filter { !$0.succeeded }.count,
            entries: entries
        )
    }

    public func history() async -> [TrashITCLIHistoryEntry] {
        await receiptStore.loadAll().map {
            TrashITCLIHistoryEntry(
                receiptID: $0.id,
                finishedAt: $0.finishedAt,
                processedBytes: $0.processedBytes,
                successCount: $0.successCount,
                failureCount: $0.failureCount
            )
        }
    }

    private func scanItems(configuration: TrashITCLIConfiguration) async -> (items: [CleanupItem], issues: [ScanIssue]) {
        let settings = makeSettings(configuration)
        let stream = await scanner.progressStream(settings: settings)
        var items: [CleanupItem] = []
        var issues: [ScanIssue] = []

        for await progress in stream {
            items.append(contentsOf: progress.result.items.filter { item in
                item.url.map(settings.includes) ?? true
            })
            issues.append(contentsOf: progress.result.issues)
        }

        var seenLocations = Set<String>()
        let uniqueItems = items.filter { item in
            let key = item.url?.standardizedFileURL.path ?? "\(item.source):\(item.id.uuidString)"
            return seenLocations.insert(key).inserted
        }
        return (
            uniqueItems.sorted {
                if $0.safety != $1.safety { return $0.safety < $1.safety }
                return $0.allocatedBytes > $1.allocatedBytes
            },
            issues
        )
    }

    private func makeSettings(_ configuration: TrashITCLIConfiguration) -> ScannerSettings {
        var settings = ScannerSettings.defaults
        if !configuration.paths.isEmpty {
            settings.scanRoots = configuration.paths.map(resolvePath)
        }
        settings.excludedPaths = configuration.excludedPaths.map(resolvePath)
        settings.oldFileDays = max(1, configuration.oldFileDays)
        settings.minimumLargeFileBytes = max(0, configuration.minimumLargeFileBytes)
        settings.minimumCacheBytes = max(0, configuration.minimumCacheBytes)
        return settings
    }

    private func resolvePath(_ path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expanded)
            .standardizedFileURL
    }

    private func makeScanReport(
        items: [CleanupItem],
        issues: [ScanIssue],
        selection: TrashITCLISelection?
    ) -> TrashITCLIScanReport {
        let mappedItems = items.map { item in
            let selected = selection.map { item.recommendations.contains($0.recommendation) } ?? false
            return TrashITCLIItem(
                id: item.id,
                name: item.name,
                path: item.url?.path,
                category: item.category.rawValue,
                categoryTitle: item.category.title,
                safety: item.safety.title,
                action: item.action.title,
                allocatedBytes: item.allocatedBytes,
                reason: item.reason,
                consequence: item.consequence,
                recommendations: item.recommendations.map(\.rawValue).sorted(),
                selected: selected,
                keeperPath: item.duplicateEvidence?.keeperURL.path
            )
        }
        return TrashITCLIScanReport(
            scannedAt: Date(),
            selection: selection,
            totalBytes: mappedItems.reduce(0) { $0 + $1.allocatedBytes },
            selectedCount: mappedItems.filter(\.selected).count,
            selectedBytes: mappedItems.filter(\.selected).reduce(0) { $0 + $1.allocatedBytes },
            items: mappedItems,
            issues: issues.map { TrashITCLIIssue(scanner: $0.scanner, message: $0.message) }
        )
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
