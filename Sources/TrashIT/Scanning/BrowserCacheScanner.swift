import Foundation

struct BrowserCacheScanner: CleanupScanning {
    let id = "browser-caches"

    private struct Rule: Sendable {
        let relativePath: String
        let name: String
        let bundleIdentifier: String
    }

    // These are cache-container leaves only. Browser profiles, cookies, sessions,
    // credentials, bookmarks, extensions, and downloads are deliberately outside them.
    private let rules: [Rule] = [
        Rule(relativePath: "Library/Caches/com.apple.Safari", name: "Safari cache", bundleIdentifier: "com.apple.Safari"),
        Rule(relativePath: "Library/Caches/Google/Chrome", name: "Google Chrome cache", bundleIdentifier: "com.google.Chrome"),
        Rule(relativePath: "Library/Caches/Chromium", name: "Chromium cache", bundleIdentifier: "org.chromium.Chromium"),
        Rule(relativePath: "Library/Caches/Microsoft Edge", name: "Microsoft Edge cache", bundleIdentifier: "com.microsoft.edgemac"),
        Rule(relativePath: "Library/Caches/Firefox", name: "Firefox cache", bundleIdentifier: "org.mozilla.firefox"),
        Rule(relativePath: "Library/Caches/company.thebrowser.Browser", name: "Arc cache", bundleIdentifier: "company.thebrowser.Browser")
    ]

    func scan(settings: ScannerSettings) async -> ScanResult {
        guard settings.includeGeneralCaches else { return ScanResult() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let budget = ScanBudget()
        let items = rules.compactMap { rule -> CleanupItem? in
            guard !budget.isExpired else { return nil }
            let url = home.appendingPathComponent(rule.relativePath, isDirectory: true)
            guard settings.includes(url), FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = FileInspection.allocatedSize(of: url)
            guard bytes >= settings.minimumCacheBytes else { return nil }
            return CleanupItem(
                name: rule.name,
                url: url,
                category: .appCaches,
                safety: .regeneratable,
                action: .deleteRegeneratable,
                allocatedBytes: bytes,
                lastUsed: FileInspection.lastUsedDate(for: url),
                reason: "A browser-owned cache container. Profile and personal-data folders are excluded.",
                consequence: "Quit the browser first. Previously visited content may load more slowly once.",
                source: id,
                recommendations: [.lowRisk],
                metadata: ["bundleCandidate": rule.bundleIdentifier, "validatedLeaf": rule.relativePath]
            )
        }
        return ScanResult(
            items: items,
            issues: budget.isExpired ? [ScanIssue(scanner: id, message: "Browser-cache scan reached its time limit. Partial results are shown.")] : []
        )
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
