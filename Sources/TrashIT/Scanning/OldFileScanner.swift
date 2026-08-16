import Foundation

struct OldFileScanner: CleanupScanning {
    let id = "old-files"

    private let archiveExtensions: Set<String> = ["dmg", "pkg", "xip", "iso", "zip", "tar", "gz", "bz2", "7z", "rar"]

    func scan(settings: ScannerSettings) async -> ScanResult {
        var result = ScanResult()
        let budget = ScanBudget(seconds: 20)
        for root in settings.scanRoots {
            guard !budget.isExpired else { break }
            let rootResult = scanRoot(root, settings: settings, budget: budget)
            result.items.append(contentsOf: rootResult.items)
            result.issues.append(contentsOf: rootResult.issues)
        }
        if budget.isExpired {
            result.issues.append(ScanIssue(scanner: id, message: "Old-file scan reached its 20-second limit. Narrower scan folders provide more complete results."))
        }
        return result
    }

    private func scanRoot(_ root: URL, settings: ScannerSettings, budget: ScanBudget) -> ScanResult {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ScanResult(issues: [ScanIssue(scanner: id, message: "Scan folder is unavailable: \(root.path)")])
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
            .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .contentAccessDateKey,
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return ScanResult() }

        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.oldFileDays, to: Date()) ?? .distantPast
        var result = ScanResult()
        var visited = 0

        for case let url as URL in enumerator {
            guard !budget.isExpired else { break }
            visited += 1
            if visited > 100_000 {
                result.issues.append(ScanIssue(scanner: id, message: "Stopped after 100,000 items in \(root.path). Add a narrower scan folder for complete results."))
                break
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }

            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let lastUsed = FileInspection.lastUsedDate(for: url) ?? values.contentModificationDate
            let isOld = lastUsed.map { $0 < cutoff } ?? false
            let isLarge = bytes >= settings.minimumLargeFileBytes
            let fileExtension = url.pathExtension.lowercased()
            let isArchive = archiveExtensions.contains(fileExtension)

            if values.isUbiquitousItem == true,
               values.ubiquitousItemIsUploaded == true,
               values.ubiquitousItemIsUploading != true,
               values.ubiquitousItemUploadingError == nil,
               bytes > 0,
               isOld {
                result.items.append(CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .cloudCopies,
                    safety: .redownloadable,
                    action: .evictCloudCopy,
                    allocatedBytes: bytes,
                    lastUsed: lastUsed,
                    reason: "The iCloud item reports that it is uploaded and has an old local copy.",
                    consequence: "The file remains in iCloud and downloads again when opened.",
                    source: id,
                    defaultSelected: false
                ))
                continue
            }

            if likelyDuplicate(url) {
                result.items.append(CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .duplicates,
                    safety: .reviewRequired,
                    action: .moveToTrash,
                    allocatedBytes: bytes,
                    lastUsed: lastUsed,
                    reason: "The numbered filename and a same-sized original suggest this is a duplicate download.",
                    consequence: "This is only a filename-and-size match; compare the files before moving it to Trash.",
                    source: id,
                    defaultSelected: false
                ))
            } else if isArchive {
                result.items.append(CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .archives,
                    safety: .reviewRequired,
                    action: .moveToTrash,
                    allocatedBytes: bytes,
                    lastUsed: lastUsed,
                    reason: "An installer or archive in a selected scan folder.",
                    consequence: "You may need to download or recreate this archive again.",
                    source: id,
                    defaultSelected: false
                ))
            } else if isOld && isLarge {
                result.items.append(CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .oldFiles,
                    safety: .reviewRequired,
                    action: .moveToTrash,
                    allocatedBytes: bytes,
                    lastUsed: lastUsed,
                    reason: "Larger than \(Formatting.bytes(settings.minimumLargeFileBytes)) and not used for at least \(settings.oldFileDays) days.",
                    consequence: "This is a user file. Open or reveal it and verify its contents first.",
                    source: id,
                    defaultSelected: false
                ))
            }
        }
        return result
    }

    private func likelyDuplicate(_ url: URL) -> Bool {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let normalized = stem.replacingOccurrences(
            of: #" \([0-9]+\)$"#,
            with: "",
            options: .regularExpression
        )
        guard normalized != stem else { return false }
        let baseName = ext.isEmpty ? normalized : "\(normalized).\(ext)"
        let original = url.deletingLastPathComponent().appendingPathComponent(baseName)
        guard FileManager.default.fileExists(atPath: original.path) else { return false }
        let candidateSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let originalSize = (try? original.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
        return candidateSize >= 0 && candidateSize == originalSize
    }
}
