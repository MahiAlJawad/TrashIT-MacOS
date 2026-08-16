import Foundation

struct DeveloperCacheScanner: CleanupScanning {
    let id = "developer-caches"

    private struct CacheRule: Sendable {
        let relativePath: String
        let name: String
        let consequence: String
    }

    private let rules: [CacheRule] = [
        CacheRule(relativePath: "Library/Caches/Homebrew", name: "Homebrew downloads", consequence: "Homebrew may download packages again."),
        CacheRule(relativePath: ".npm/_cacache", name: "npm cache", consequence: "npm may download packages again."),
        CacheRule(relativePath: "Library/Caches/Yarn", name: "Yarn cache", consequence: "Yarn may download packages again."),
        CacheRule(relativePath: "Library/pnpm/store", name: "pnpm store", consequence: "pnpm may download packages and relink projects again."),
        CacheRule(relativePath: ".gradle/caches", name: "Gradle cache", consequence: "Gradle will resolve dependencies and rebuild cached transforms."),
        CacheRule(relativePath: ".m2/repository", name: "Maven repository cache", consequence: "Maven will download dependencies again."),
        CacheRule(relativePath: "Library/Caches/CocoaPods", name: "CocoaPods cache", consequence: "CocoaPods may download pod sources again."),
        CacheRule(relativePath: "Library/Caches/org.swift.swiftpm", name: "SwiftPM cache", consequence: "Swift Package Manager may download dependencies again."),
        CacheRule(relativePath: "Library/org.swift.swiftpm", name: "SwiftPM repositories", consequence: "Swift Package Manager may clone package repositories again."),
        CacheRule(relativePath: ".pub-cache", name: "Dart and Flutter packages", consequence: "Pub will download packages again."),
        CacheRule(relativePath: "Library/Caches/JetBrains", name: "JetBrains cache", consequence: "JetBrains applications will rebuild indexes and caches.")
    ]

    func scan(settings: ScannerSettings) async -> ScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let budget = ScanBudget()
        let items = rules.compactMap { rule -> CleanupItem? in
            guard !budget.isExpired else { return nil }
            let url = home.appendingPathComponent(rule.relativePath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = FileInspection.allocatedSize(of: url)
            guard bytes >= settings.minimumCacheBytes else { return nil }
            return CleanupItem(
                name: rule.name,
                url: url,
                category: .developerCaches,
                safety: .redownloadable,
                action: .deleteRegeneratable,
                allocatedBytes: bytes,
                lastUsed: FileInspection.lastUsedDate(for: url),
                reason: "A known package-manager or development-tool cache.",
                consequence: rule.consequence,
                source: id,
                defaultSelected: false
            )
        }
        return ScanResult(
            items: items,
            issues: budget.isExpired ? [ScanIssue(scanner: id, message: "Developer-cache scan reached its 15-second limit. Partial results are shown.")] : []
        )
    }
}
