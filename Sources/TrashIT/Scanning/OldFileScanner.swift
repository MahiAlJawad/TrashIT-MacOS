import Foundation
import CryptoKit

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
        var duplicateGroupIDs: [URL: UUID] = [:]

        for case let url as URL in enumerator {
            guard !budget.isExpired else { break }
            visited += 1
            if visited > 100_000 {
                result.issues.append(ScanIssue(scanner: id, message: "Stopped after 100,000 items in \(root.path). Add a narrower scan folder for complete results."))
                break
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  settings.includes(url) else { continue }

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
                    recommendations: [.lowRisk]
                ))
                continue
            }

            if let duplicate = verifiedDuplicate(
                url,
                budget: budget,
                groupIDs: &duplicateGroupIDs
            ) {
                result.items.append(CleanupItem(
                    name: url.lastPathComponent,
                    url: url,
                    category: .duplicates,
                    safety: .reviewRequired,
                    action: .moveToTrash,
                    allocatedBytes: bytes,
                    lastUsed: lastUsed,
                    reason: "Its contents exactly match \(duplicate.keeperURL.lastPathComponent).",
                    consequence: "The matching original is kept. This copy will move to Bin and can be restored.",
                    source: id,
                    recommendations: [.verifiedDuplicate],
                    duplicateEvidence: duplicate
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
                    source: id
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
                    source: id
                ))
            }
        }
        return result
    }

    private func verifiedDuplicate(
        _ url: URL,
        budget: ScanBudget,
        groupIDs: inout [URL: UUID]
    ) -> DuplicateEvidence? {
        guard !budget.isExpired,
              let original = originalURL(forCopy: url),
              FileManager.default.fileExists(atPath: original.path),
              !FileInspection.isSymbolicLink(original),
              logicalSize(of: url) == logicalSize(of: original),
              logicalSize(of: url) >= 0,
              let candidateDigest = digest(of: url, budget: budget),
              let originalDigest = digest(of: original, budget: budget),
              candidateDigest == originalDigest else { return nil }

        let keeper = original.standardizedFileURL
        let groupID = groupIDs[keeper] ?? UUID()
        groupIDs[keeper] = groupID
        return DuplicateEvidence(groupID: groupID, keeperURL: keeper)
    }

    private func originalURL(forCopy url: URL) -> URL? {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let patterns = [
            #"^(.*) \([1-9][0-9]*\)$"#,
            #"^(.*) copy(?: [1-9][0-9]*)?$"#
        ]
        var normalized: String?
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(
                    in: stem,
                    range: NSRange(stem.startIndex..., in: stem)
                  ),
                  let range = Range(match.range(at: 1), in: stem) else { continue }
            normalized = String(stem[range])
            break
        }
        guard let normalized, !normalized.isEmpty else { return nil }
        let baseName = ext.isEmpty ? normalized : "\(normalized).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(baseName)
    }

    private func logicalSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
    }

    private func digest(of url: URL, budget: ScanBudget) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while !budget.isExpired {
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else {
                    return hasher.finalize()
                }
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return nil
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
