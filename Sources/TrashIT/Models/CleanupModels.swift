import Foundation

enum CleanupCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case xcode
    case simulators
    case developerCaches
    case appCaches
    case logs
    case downloads
    case oldFiles
    case duplicates
    case archives
    case backups
    case cloudCopies
    case trash
    case appLeftovers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcode: "Xcode"
        case .simulators: "Simulators"
        case .developerCaches: "Developer caches"
        case .appCaches: "Application caches"
        case .logs: "Logs & reports"
        case .downloads: "Downloads"
        case .oldFiles: "Old large files"
        case .duplicates: "Verified duplicates"
        case .archives: "Archives & installers"
        case .backups: "Device backups"
        case .cloudCopies: "Cloud local copies"
        case .trash: "Trash"
        case .appLeftovers: "App leftovers"
        }
    }

    var symbolName: String {
        switch self {
        case .xcode: "hammer"
        case .simulators: "iphone.gen3"
        case .developerCaches: "terminal"
        case .appCaches: "shippingbox"
        case .logs: "doc.text.magnifyingglass"
        case .downloads: "arrow.down.circle"
        case .oldFiles: "clock.arrow.circlepath"
        case .duplicates: "square.on.square"
        case .archives: "archivebox"
        case .backups: "externaldrive"
        case .cloudCopies: "icloud.and.arrow.down"
        case .trash: "trash"
        case .appLeftovers: "app.dashed"
        }
    }
}

enum SafetyLevel: Int, CaseIterable, Codable, Comparable, Sendable {
    case regeneratable = 0
    case redownloadable = 1
    case reviewRequired = 2
    case irreplaceable = 3

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .regeneratable: "Regenerable"
        case .redownloadable: "Re-downloadable"
        case .reviewRequired: "Review required"
        case .irreplaceable: "Potentially irreplaceable"
        }
    }

    var explanation: String {
        switch self {
        case .regeneratable: "The system or a development tool can rebuild this data."
        case .redownloadable: "This can be restored, but may require internet access or external hardware."
        case .reviewRequired: "This may be useful user or application data. Inspect it before cleaning."
        case .irreplaceable: "This may be the only copy. TrashIT will never select it automatically."
        }
    }
}

enum CleanupRecommendation: String, Codable, Hashable, Sendable {
    case lowRisk
    case outdatedSimulator
    case verifiedDuplicate
}

enum SmartSelectionRule: String, CaseIterable, Identifiable, Sendable {
    case safeCleanup
    case outdatedSimulators
    case duplicateCopies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safeCleanup: "Safe cleanup"
        case .outdatedSimulators: "Older simulator runtimes"
        case .duplicateCopies: "Duplicate copies"
        }
    }

    var explanation: String {
        switch self {
        case .safeCleanup:
            "Selected items TrashIT can regenerate or download again."
        case .outdatedSimulators:
            "Selected older runtime releases while keeping the newest installed release in every major version."
        case .duplicateCopies:
            "Selected filename copies whose contents exactly match the original file being kept."
        }
    }

    var symbolName: String {
        switch self {
        case .safeCleanup: "checkmark.shield"
        case .outdatedSimulators: "iphone.gen3.radiowaves.left.and.right"
        case .duplicateCopies: "square.on.square"
        }
    }

    var recommendation: CleanupRecommendation {
        switch self {
        case .safeCleanup: .lowRisk
        case .outdatedSimulators: .outdatedSimulator
        case .duplicateCopies: .verifiedDuplicate
        }
    }
}

struct DuplicateEvidence: Hashable, Codable, Sendable {
    let groupID: UUID
    let keeperURL: URL
}

struct CleanupNavigationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let category: CleanupCategory?
    let smartSelection: SmartSelectionRule?

    init(
        id: UUID = UUID(),
        category: CleanupCategory? = nil,
        smartSelection: SmartSelectionRule? = nil
    ) {
        self.id = id
        self.category = category
        self.smartSelection = smartSelection
    }
}

enum CleanupAction: Hashable, Codable, Sendable {
    case deleteRegeneratable
    case deletePermanently
    case moveToTrash
    case evictCloudCopy
    case deleteSimulatorDevice(udid: String)
    case deleteSimulatorRuntime(identifier: String)
    case pruneDocker
    case cleanToolCache(ToolCleanupKind)

    var title: String {
        switch self {
        case .deleteRegeneratable, .moveToTrash: "Move to Bin"
        case .deletePermanently: "Delete permanently"
        case .evictCloudCopy: "Remove local copy"
        case .deleteSimulatorDevice: "Delete simulator"
        case .deleteSimulatorRuntime: "Uninstall runtime"
        case .pruneDocker: "Prune with Docker"
        case .cleanToolCache: "Clean with owning tool"
        }
    }

    var usesBin: Bool {
        switch self {
        case .deleteRegeneratable, .moveToTrash: true
        default: false
        }
    }
}

enum ToolCleanupKind: String, Hashable, Codable, Sendable {
    case npm
    case pnpm
    case pip
    case uv
    case goBuild
    case goModules
    case bun
    case corepack

    var executableName: String {
        switch self {
        case .goBuild, .goModules: "go"
        default: rawValue
        }
    }

    var arguments: [String] {
        switch self {
        case .npm: ["cache", "clean", "--force"]
        case .pnpm: ["store", "prune"]
        case .pip: ["cache", "purge"]
        case .uv: ["cache", "prune"]
        case .goBuild: ["clean", "-cache"]
        case .goModules: ["clean", "-modcache"]
        case .bun: ["pm", "cache", "rm"]
        case .corepack: ["cache", "clean"]
        }
    }
}

struct CleanupItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let url: URL?
    let category: CleanupCategory
    let safety: SafetyLevel
    let action: CleanupAction
    let allocatedBytes: Int64
    let lastUsed: Date?
    let reason: String
    let consequence: String
    let source: String
    let recommendations: Set<CleanupRecommendation>
    let duplicateEvidence: DuplicateEvidence?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        url: URL?,
        category: CleanupCategory,
        safety: SafetyLevel,
        action: CleanupAction,
        allocatedBytes: Int64,
        lastUsed: Date? = nil,
        reason: String,
        consequence: String,
        source: String,
        recommendations: Set<CleanupRecommendation> = [],
        duplicateEvidence: DuplicateEvidence? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.category = category
        self.safety = safety
        self.action = action
        self.allocatedBytes = allocatedBytes
        self.lastUsed = lastUsed
        self.reason = reason
        self.consequence = consequence
        self.source = source
        self.recommendations = recommendations
        self.duplicateEvidence = duplicateEvidence
        self.metadata = metadata
    }
}

struct ScanIssue: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let scanner: String
    let message: String

    init(id: UUID = UUID(), scanner: String, message: String) {
        self.id = id
        self.scanner = scanner
        self.message = message
    }
}

struct ScanResult: Sendable {
    var items: [CleanupItem] = []
    var issues: [ScanIssue] = []
}

struct ScanSnapshot: Sendable {
    let date: Date
    let items: [CleanupItem]
    let issues: [ScanIssue]

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
}

struct CleanupReceipt: Identifiable, Codable, Sendable {
    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        let itemName: String
        let originalPath: String?
        let bytes: Int64
        let action: CleanupAction
        let succeeded: Bool
        let message: String
    }

    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let entries: [Entry]

    var processedBytes: Int64 {
        entries.filter(\.succeeded).reduce(0) { $0 + $1.bytes }
    }

    var successCount: Int { entries.filter(\.succeeded).count }
    var failureCount: Int { entries.filter { !$0.succeeded }.count }
    var binCount: Int { entries.filter { $0.succeeded && $0.action.usesBin }.count }
    var binBytes: Int64 {
        entries.filter { $0.succeeded && $0.action.usesBin }.reduce(0) { $0 + $1.bytes }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
