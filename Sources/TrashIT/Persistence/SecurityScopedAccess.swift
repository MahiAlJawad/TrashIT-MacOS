import Foundation

enum SecurityScopedAccess {
    private static let key = "TrashIT.SecurityScopedFolders"

    static func remember(_ url: URL) {
        #if TRASHIT_APP_STORE
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        bookmarks[url.standardizedFileURL.path] = data
        UserDefaults.standard.set(bookmarks, forKey: key)
        _ = url.startAccessingSecurityScopedResource()
        #endif
    }

    static func forget(_ url: URL) {
        #if TRASHIT_APP_STORE
        var bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: url.standardizedFileURL.path)
        UserDefaults.standard.set(bookmarks, forKey: key)
        url.stopAccessingSecurityScopedResource()
        #endif
    }

    static func restoreAll() -> [URL] {
        #if TRASHIT_APP_STORE
        let bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        return bookmarks.values.compactMap { data in
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), url.startAccessingSecurityScopedResource() else { return nil }
            if stale { remember(url) }
            return url.standardizedFileURL
        }
        #else
        return []
        #endif
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
