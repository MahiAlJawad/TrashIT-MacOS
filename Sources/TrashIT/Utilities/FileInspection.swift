import Foundation
import CoreServices

enum FileInspection {
    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .fileResourceIdentifierKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .isPackageKey
    ]

    static func allocatedSize(
        of root: URL,
        limit: Int = 50_000,
        timeLimit: TimeInterval = 1.5
    ) -> Int64 {
        guard let values = try? root.resourceValues(forKeys: sizeKeys),
              values.isSymbolicLink != true else { return 0 }

        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard values.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(sizeKeys),
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
              ) else { return 0 }

        var total: Int64 = 0
        var seenIdentifiers = Set<AnyHashable>()
        var count = 0
        let deadline = Date().addingTimeInterval(timeLimit)

        for case let url as URL in enumerator {
            count += 1
            if count > limit || Date() >= deadline { break }
            guard let child = try? url.resourceValues(forKeys: sizeKeys) else { continue }
            if child.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard child.isRegularFile == true else { continue }
            if let identifier = child.fileResourceIdentifier as? AnyHashable {
                guard seenIdentifiers.insert(identifier).inserted else { continue }
            }
            total += Int64(child.totalFileAllocatedSize ?? child.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func lastUsedDate(for url: URL) -> Date? {
        if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return value
        }
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        return values?.contentAccessDate ?? values?.contentModificationDate
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
