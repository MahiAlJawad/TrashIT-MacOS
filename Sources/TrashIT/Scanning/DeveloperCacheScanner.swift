import Foundation

struct DeveloperCacheScanner: CleanupScanning {
    let id = "developer-caches"

    private struct CacheRule: Sendable {
        let relativePath: String
        let name: String
        let safety: SafetyLevel
        let action: CleanupAction
        let reason: String
        let consequence: String
        let recommendations: Set<CleanupRecommendation>
        let blockingProcesses: [String]

        init(
            _ relativePath: String,
            name: String,
            safety: SafetyLevel = .redownloadable,
            action: CleanupAction = .deleteRegeneratable,
            reason: String,
            consequence: String,
            recommended: Bool = true,
            blockingProcesses: [String] = []
        ) {
            self.relativePath = relativePath
            self.name = name
            self.safety = safety
            self.action = action
            self.reason = reason
            self.consequence = consequence
            recommendations = recommended ? [.lowRisk] : []
            self.blockingProcesses = blockingProcesses
        }
    }

    // Every path is a bounded cache/download leaf owned by the named tool.
    private let rules: [CacheRule] = [
        CacheRule(
            "Library/Caches/Homebrew/downloads", name: "Homebrew downloads",
            reason: "Downloaded Homebrew archives; installed formulae and metadata are outside this folder.",
            consequence: "Homebrew will download an archive again when it is needed.", blockingProcesses: ["brew"]
        ),
        CacheRule(
            ".npm/_cacache", name: "npm content cache", action: .cleanToolCache(.npm),
            reason: "npm's content-addressed download cache, cleaned through npm itself.",
            consequence: "npm will verify and download packages again.", blockingProcesses: ["npm", "node"]
        ),
        CacheRule(
            "Library/pnpm/store", name: "Unused pnpm packages", action: .cleanToolCache(.pnpm),
            reason: "pnpm decides which unreferenced packages can be pruned from its store.",
            consequence: "pnpm may download a pruned package when a project needs it again.", blockingProcesses: ["pnpm", "node"]
        ),
        CacheRule(
            "Library/Caches/pip", name: "pip download cache", action: .cleanToolCache(.pip),
            reason: "pip-managed HTTP and wheel cache, cleaned through pip.",
            consequence: "pip will rebuild or download cached packages again.", blockingProcesses: ["pip", "pip3", "python", "python3"]
        ),
        CacheRule(
            ".cache/uv", name: "Unused uv cache entries", action: .cleanToolCache(.uv),
            reason: "uv-managed package cache, pruned through uv.",
            consequence: "uv may download or rebuild pruned packages again.", blockingProcesses: ["uv"]
        ),
        CacheRule(
            "Library/Caches/go-build", name: "Go build cache", safety: .regeneratable, action: .cleanToolCache(.goBuild),
            reason: "Compiled Go build artifacts, cleaned through the Go tool.",
            consequence: "The next Go build will recompile affected packages.", blockingProcesses: ["go"]
        ),
        CacheRule(
            "go/pkg/mod/cache", name: "Go module download cache", action: .cleanToolCache(.goModules),
            reason: "Downloaded Go modules, cleaned through the Go tool.",
            consequence: "Go will download modules again when a build requires them.", blockingProcesses: ["go"]
        ),
        CacheRule(
            ".bun/install/cache", name: "Bun package cache", action: .cleanToolCache(.bun),
            reason: "Bun's package download cache, cleaned through Bun.",
            consequence: "Bun will download packages again.", blockingProcesses: ["bun"]
        ),
        CacheRule(
            ".cache/node/corepack", name: "Corepack package-manager cache", action: .cleanToolCache(.corepack),
            reason: "Package-manager archives managed by Corepack.",
            consequence: "Corepack will download the requested package-manager version again.", blockingProcesses: ["corepack", "node"]
        ),
        CacheRule(
            ".rustup/downloads", name: "Rustup downloads",
            reason: "Completed toolchain downloads; installed toolchains are stored elsewhere.",
            consequence: "Rustup will download an archive again if it is required.", blockingProcesses: ["rustup"]
        ),
        CacheRule(
            ".rustup/tmp", name: "Rustup temporary files", safety: .regeneratable,
            reason: "Temporary Rustup transfer and installation data.",
            consequence: "Rustup recreates this folder when needed.", blockingProcesses: ["rustup"]
        ),
        CacheRule(
            ".cargo/registry/cache", name: "Cargo crate archives",
            reason: "Downloaded crate archives; source checkouts and installed commands are outside this leaf.",
            consequence: "Cargo will download crate archives again.", recommended: false, blockingProcesses: ["cargo"]
        ),
        CacheRule(
            ".android/cache", name: "Android SDK download cache",
            reason: "Temporary SDK Manager downloads; installed SDK packages are outside this folder.",
            consequence: "Android SDK Manager will download packages again.", blockingProcesses: ["studio", "sdkmanager"]
        ),
        CacheRule(
            ".m2/repository", name: "Maven local repository", safety: .reviewRequired,
            reason: "Maven's local repository can include locally installed artifacts that do not exist remotely.",
            consequence: "Remote dependencies can be downloaded again, but local-only artifacts may be lost.", recommended: false, blockingProcesses: ["mvn", "java"]
        ),
        CacheRule(
            ".pub-cache", name: "Dart and Flutter package store", safety: .reviewRequired,
            reason: "The shared Pub store may include path or unpublished package state requiring manual review.",
            consequence: "Published packages can be downloaded again; verify local package sources first.", recommended: false, blockingProcesses: ["dart", "flutter"]
        )
    ]

    func scan(settings: ScannerSettings) async -> ScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let budget = ScanBudget()
        var items = rules.compactMap { rule -> CleanupItem? in
            guard !budget.isExpired else { return nil }
            return makeItem(rule: rule, url: home.appendingPathComponent(rule.relativePath, isDirectory: true), settings: settings)
        }
        items.append(contentsOf: gradleItems(home: home, settings: settings, budget: budget))
        return ScanResult(
            items: items,
            issues: budget.isExpired ? [ScanIssue(scanner: id, message: "Developer-cache scan reached its 15-second limit. Partial results are shown.")] : []
        )
    }

    private func makeItem(rule: CacheRule, url: URL, settings: ScannerSettings) -> CleanupItem? {
        guard settings.includes(url), FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = FileInspection.allocatedSize(of: url)
        guard bytes >= settings.minimumCacheBytes else { return nil }
        var metadata: [String: String] = ["validatedLeaf": rule.relativePath]
        if !rule.blockingProcesses.isEmpty { metadata["blockingProcesses"] = rule.blockingProcesses.joined(separator: ",") }
        return CleanupItem(
            name: rule.name, url: url, category: .developerCaches, safety: rule.safety, action: rule.action,
            allocatedBytes: bytes, lastUsed: FileInspection.lastUsedDate(for: url), reason: rule.reason,
            consequence: rule.consequence, source: id, recommendations: rule.recommendations, metadata: metadata
        )
    }

    private func gradleItems(home: URL, settings: ScannerSettings, budget: ScanBudget) -> [CleanupItem] {
        let gradle = home.appendingPathComponent(".gradle", isDirectory: true)
        let fixedLeaves = ["daemon", "workers"].map { gradle.appendingPathComponent($0, isDirectory: true) }
        let caches = gradle.appendingPathComponent("caches", isDirectory: true)
        let buildCaches = ((try? FileManager.default.contentsOfDirectory(
            at: caches, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.lastPathComponent.hasPrefix("build-cache-") }

        return (fixedLeaves + buildCaches).compactMap { url in
            guard !budget.isExpired else { return nil }
            let relativePath = url.path.replacingOccurrences(of: home.path + "/", with: "")
            let rule = CacheRule(
                relativePath, name: "Gradle \(url.lastPathComponent) cache", safety: .regeneratable,
                reason: "A bounded Gradle-generated cache leaf; dependency and wrapper stores are excluded.",
                consequence: "Gradle may restart workers or rebuild cached outputs.", blockingProcesses: ["gradle", "java"]
            )
            return makeItem(rule: rule, url: url, settings: settings)
        }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
