import Foundation

struct ScannerSettings: Codable, Equatable, Sendable {
    var scanRoots: [URL]
    var oldFileDays: Int
    var minimumLargeFileBytes: Int64
    var minimumCacheBytes: Int64
    var includeGeneralCaches: Bool
    var includeAppLeftovers: Bool
    var includeTrash: Bool
    var includeDeviceBackups: Bool
    var excludedPaths: [URL]

    init(
        scanRoots: [URL],
        oldFileDays: Int,
        minimumLargeFileBytes: Int64,
        minimumCacheBytes: Int64,
        includeGeneralCaches: Bool,
        includeAppLeftovers: Bool,
        includeTrash: Bool,
        includeDeviceBackups: Bool,
        excludedPaths: [URL] = []
    ) {
        self.scanRoots = scanRoots
        self.oldFileDays = oldFileDays
        self.minimumLargeFileBytes = minimumLargeFileBytes
        self.minimumCacheBytes = minimumCacheBytes
        self.includeGeneralCaches = includeGeneralCaches
        self.includeAppLeftovers = includeAppLeftovers
        self.includeTrash = includeTrash
        self.includeDeviceBackups = includeDeviceBackups
        self.excludedPaths = excludedPaths
    }

    private enum CodingKeys: String, CodingKey {
        case scanRoots, oldFileDays, minimumLargeFileBytes, minimumCacheBytes
        case includeGeneralCaches, includeAppLeftovers, includeTrash, includeDeviceBackups
        case excludedPaths
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scanRoots = try values.decodeIfPresent([URL].self, forKey: .scanRoots) ?? defaults.scanRoots
        oldFileDays = try values.decodeIfPresent(Int.self, forKey: .oldFileDays) ?? defaults.oldFileDays
        minimumLargeFileBytes = try values.decodeIfPresent(Int64.self, forKey: .minimumLargeFileBytes) ?? defaults.minimumLargeFileBytes
        minimumCacheBytes = try values.decodeIfPresent(Int64.self, forKey: .minimumCacheBytes) ?? defaults.minimumCacheBytes
        includeGeneralCaches = try values.decodeIfPresent(Bool.self, forKey: .includeGeneralCaches) ?? defaults.includeGeneralCaches
        includeAppLeftovers = try values.decodeIfPresent(Bool.self, forKey: .includeAppLeftovers) ?? defaults.includeAppLeftovers
        includeTrash = try values.decodeIfPresent(Bool.self, forKey: .includeTrash) ?? defaults.includeTrash
        includeDeviceBackups = try values.decodeIfPresent(Bool.self, forKey: .includeDeviceBackups) ?? defaults.includeDeviceBackups
        excludedPaths = try values.decodeIfPresent([URL].self, forKey: .excludedPaths) ?? []
    }

    func includes(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        return !excludedPaths.contains { excluded in
            let path = excluded.standardizedFileURL.path
            return candidate == path || candidate.hasPrefix(path + "/")
        }
    }

    static var defaults: ScannerSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if TRASHIT_APP_STORE
        let defaultRoots: [URL] = []
        #else
        let defaultRoots = [home.appendingPathComponent("Downloads", isDirectory: true)]
        #endif
        return ScannerSettings(
            scanRoots: defaultRoots,
            oldFileDays: 180,
            minimumLargeFileBytes: 250 * 1_024 * 1_024,
            minimumCacheBytes: 100 * 1_024 * 1_024,
            includeGeneralCaches: true,
            includeAppLeftovers: false,
            includeTrash: true,
            includeDeviceBackups: true,
            excludedPaths: []
        )
    }
}

struct VolumeCapacity: Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> VolumeCapacity? {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            guard let total = values.volumeTotalCapacity else { return nil }
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            return VolumeCapacity(total: Int64(total), available: available)
        } catch {
            return nil
        }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
