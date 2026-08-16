import Foundation

struct GeneralStorageScanner: CleanupScanning {
    let id = "general-storage"

    func scan(settings: ScannerSettings) async -> ScanResult {
        var items: [CleanupItem] = []
        let budget = ScanBudget(seconds: 18)
        if settings.includeGeneralCaches {
            items.append(contentsOf: scanCaches(settings: settings, budget: budget))
            if !budget.isExpired {
                items.append(contentsOf: scanLogs(settings: settings, budget: budget))
            }
        }
        if settings.includeTrash && !budget.isExpired {
            items.append(contentsOf: scanTrash(budget: budget))
        }
        if settings.includeDeviceBackups && !budget.isExpired {
            items.append(contentsOf: scanBackups(budget: budget))
        }
        if settings.includeAppLeftovers && !budget.isExpired {
            items.append(contentsOf: scanAppLeftovers(settings: settings, budget: budget))
        }
        return ScanResult(
            items: items,
            issues: budget.isExpired ? [ScanIssue(scanner: id, message: "Cache scan reached its 18-second limit. Partial results are shown; lowering the cache-size threshold may make scans slower.")] : []
        )
    }

    private func scanCaches(settings: ScannerSettings, budget: ScanBudget) -> [CleanupItem] {
        let root = home.appendingPathComponent("Library/Caches", isDirectory: true)
        return FileInspection.children(of: root).compactMap { url in
            guard !budget.isExpired else { return nil }
            let bytes = FileInspection.allocatedSize(of: url)
            guard bytes >= settings.minimumCacheBytes else { return nil }
            return CleanupItem(
                name: readableName(url.lastPathComponent),
                url: url,
                category: .appCaches,
                safety: .reviewRequired,
                action: .deleteRegeneratable,
                allocatedBytes: bytes,
                lastUsed: FileInspection.lastUsedDate(for: url),
                reason: "A large application cache.",
                consequence: "The owning app may reindex, sign in again, or download data. Quit it before cleaning.",
                source: id,
                defaultSelected: false,
                metadata: ["bundleCandidate": url.lastPathComponent]
            )
        }
    }

    private func scanLogs(settings: ScannerSettings, budget: ScanBudget) -> [CleanupItem] {
        let logsRoot = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let reportsRoot = logsRoot.appendingPathComponent("DiagnosticReports", isDirectory: true)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let candidates = FileInspection.children(of: logsRoot).filter { $0 != reportsRoot }
            + FileInspection.children(of: reportsRoot)
        return candidates.compactMap { url in
                guard !budget.isExpired else { return nil }
                let lastUsed = FileInspection.lastUsedDate(for: url)
                guard lastUsed.map({ $0 < cutoff }) ?? true else { return nil }
                let bytes = FileInspection.allocatedSize(of: url)
                guard bytes >= min(settings.minimumCacheBytes, 20 * 1_024 * 1_024) else { return nil }
                return CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .logs,
                    safety: .regeneratable,
                    action: .deleteRegeneratable,
                    allocatedBytes: bytes,
                    lastUsed: lastUsed,
                    reason: "Logs or diagnostic reports older than 30 days.",
                    consequence: "Historical diagnostic information will no longer be available.",
                    source: id,
                    defaultSelected: false
                )
        }
    }

    private func scanTrash(budget: ScanBudget) -> [CleanupItem] {
        let root = home.appendingPathComponent(".Trash", isDirectory: true)
        return FileInspection.children(of: root).compactMap { url in
            guard !budget.isExpired else { return nil }
            let bytes = FileInspection.allocatedSize(of: url)
            guard bytes > 0 else { return nil }
            return CleanupItem(
                name: url.lastPathComponent,
                url: url,
                category: .trash,
                safety: .irreplaceable,
                action: .deletePermanently,
                allocatedBytes: bytes,
                lastUsed: FileInspection.lastUsedDate(for: url),
                reason: "This item is already in Trash but still occupies storage.",
                consequence: "Deletion is permanent and cannot be undone from TrashIT.",
                source: id,
                defaultSelected: false
            )
        }
    }

    private func scanBackups(budget: ScanBudget) -> [CleanupItem] {
        let root = home.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
        return FileInspection.children(of: root).compactMap { url in
            guard !budget.isExpired else { return nil }
            let bytes = FileInspection.allocatedSize(of: url)
            guard bytes > 0 else { return nil }
            return CleanupItem(
                name: url.lastPathComponent,
                url: url,
                category: .backups,
                safety: .irreplaceable,
                action: .moveToTrash,
                allocatedBytes: bytes,
                lastUsed: FileInspection.lastUsedDate(for: url),
                reason: "A local iPhone or iPad backup.",
                consequence: "You will lose this restore point. Confirm a newer backup exists before continuing.",
                source: id,
                defaultSelected: false
            )
        }
    }

    private func scanAppLeftovers(settings: ScannerSettings, budget: ScanBudget) -> [CleanupItem] {
        let installed = installedBundleIdentifiers()
        let roots = [
            home.appendingPathComponent("Library/Application Support", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        ]
        return roots.flatMap { root in
            FileInspection.children(of: root).compactMap { url -> CleanupItem? in
                guard !budget.isExpired else { return nil }
                let candidate = url.lastPathComponent.replacingOccurrences(of: "group.", with: "")
                guard looksLikeBundleIdentifier(candidate),
                      !candidate.hasPrefix("com.apple."),
                      !installed.contains(candidate) else { return nil }
                let bytes = FileInspection.allocatedSize(of: url)
                guard bytes >= settings.minimumCacheBytes else { return nil }
                return CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .appLeftovers,
                    safety: .irreplaceable,
                    action: .moveToTrash,
                    allocatedBytes: bytes,
                    lastUsed: FileInspection.lastUsedDate(for: url),
                    reason: "No installed application with the matching bundle identifier was found.",
                    consequence: "The app may exist outside standard Applications folders or this may be shared data. Verify manually.",
                    source: id,
                    defaultSelected: false,
                    metadata: ["experimental": "true"]
                )
            }
        }
    }

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private func installedBundleIdentifiers() -> Set<String> {
        let appRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        return Set(appRoots.flatMap(FileInspection.children(of:)).compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    private func looksLikeBundleIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}$"#, options: .regularExpression) != nil
    }

    private func readableName(_ value: String) -> String {
        value.replacingOccurrences(of: "com.", with: "").replacingOccurrences(of: ".", with: " · ")
    }
}
