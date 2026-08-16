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
        case .duplicates: "Likely duplicates"
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
        case .regeneratable: "Regeneratable"
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

enum CleanupAction: Hashable, Codable, Sendable {
    case deleteRegeneratable
    case deletePermanently
    case moveToTrash
    case evictCloudCopy
    case deleteSimulatorDevice(udid: String)
    case deleteSimulatorRuntime(identifier: String)
    case pruneDocker

    var title: String {
        switch self {
        case .deleteRegeneratable, .moveToTrash: "Move to Bin"
        case .deletePermanently: "Delete permanently"
        case .evictCloudCopy: "Remove local copy"
        case .deleteSimulatorDevice: "Delete simulator"
        case .deleteSimulatorRuntime: "Uninstall runtime"
        case .pruneDocker: "Prune with Docker"
        }
    }

    var usesBin: Bool {
        switch self {
        case .deleteRegeneratable, .moveToTrash: true
        default: false
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
    let defaultSelected: Bool
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
        defaultSelected: Bool = false,
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
        self.defaultSelected = defaultSelected
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
