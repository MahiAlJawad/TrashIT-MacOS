import Foundation

struct XcodeScanner: CleanupScanning {
    let id = "xcode"

    private struct Rule: Sendable {
        let relativePath: String
        let category: CleanupCategory
        let safety: SafetyLevel
        let consequence: String
        let recommended: Bool
    }

    private let rules: [Rule] = [
        Rule(
            relativePath: "Library/Developer/Xcode/DerivedData",
            category: .xcode,
            safety: .regeneratable,
            consequence: "Xcode will rebuild products and indexes the next time the project opens.",
            recommended: true
        ),
        Rule(
            relativePath: "Library/Developer/Xcode/Products",
            category: .xcode,
            safety: .regeneratable,
            consequence: "Xcode will rebuild these generated products when needed.",
            recommended: true
        ),
        Rule(
            relativePath: "Library/Developer/Xcode/DocumentationCache",
            category: .xcode,
            safety: .redownloadable,
            consequence: "Xcode may download documentation again.",
            recommended: true
        ),
        Rule(
            relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
            category: .xcode,
            safety: .redownloadable,
            consequence: "Connecting a matching device may recreate or download support files.",
            recommended: true
        ),
        Rule(
            relativePath: "Library/Developer/Xcode/watchOS DeviceSupport",
            category: .xcode,
            safety: .redownloadable,
            consequence: "Connecting a matching watch may recreate or download support files.",
            recommended: true
        ),
        Rule(
            relativePath: "Library/Developer/CoreSimulator/Caches",
            category: .simulators,
            safety: .regeneratable,
            consequence: "CoreSimulator will recreate its caches; the next launch can be slower.",
            recommended: true
        )
    ]

    func scan(settings: ScannerSettings) async -> ScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result = ScanResult()
        let budget = ScanBudget()

        for rule in rules {
            guard !budget.isExpired else { break }
            let root = home.appendingPathComponent(rule.relativePath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }

            let children = FileInspection.children(of: root)
            if children.isEmpty {
                let bytes = FileInspection.allocatedSize(of: root)
                if bytes > 0 {
                    result.items.append(makeItem(url: root, bytes: bytes, rule: rule))
                }
                continue
            }

            for child in children {
                guard !budget.isExpired else { break }
                let bytes = FileInspection.allocatedSize(of: child)
                guard bytes > 0 else { continue }
                result.items.append(makeItem(url: child, bytes: bytes, rule: rule))
            }
        }

        if !budget.isExpired {
            result.items.append(contentsOf: scanArchives(home: home, budget: budget))
        } else {
            result.issues.append(ScanIssue(scanner: id, message: "Xcode scan reached its 15-second limit. Partial results are shown."))
        }
        return result
    }

    private func makeItem(url: URL, bytes: Int64, rule: Rule) -> CleanupItem {
        CleanupItem(
            name: url.lastPathComponent,
            url: url,
            category: rule.category,
            safety: rule.safety,
            action: .deleteRegeneratable,
            allocatedBytes: bytes,
            lastUsed: FileInspection.lastUsedDate(for: url),
            reason: "Generated data in \(rule.relativePath).",
            consequence: rule.consequence,
            source: id,
            recommendations: rule.recommended ? [.lowRisk] : []
        )
    }

    private func scanArchives(home: URL, budget: ScanBudget) -> [CleanupItem] {
        let root = home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return FileInspection.children(of: root).compactMap { child in
            guard !budget.isExpired else { return nil }
            let bytes = FileInspection.allocatedSize(of: child)
            guard bytes > 0 else { return nil }
            return CleanupItem(
                name: child.lastPathComponent,
                url: child,
                category: .xcode,
                safety: .irreplaceable,
                action: .moveToTrash,
                allocatedBytes: bytes,
                lastUsed: FileInspection.lastUsedDate(for: child),
                reason: "An Xcode archive may contain a distributable build and its dSYM.",
                consequence: "Only move this to Trash if the build and symbols are preserved elsewhere.",
                source: id,
                metadata: ["kind": "Xcode archive"]
            )
        }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
