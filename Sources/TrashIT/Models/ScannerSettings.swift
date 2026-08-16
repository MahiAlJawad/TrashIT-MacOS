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
    var keepLatestSimulatorMinorPerMajor: Bool

    static var defaults: ScannerSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScannerSettings(
            scanRoots: [home.appendingPathComponent("Downloads", isDirectory: true)],
            oldFileDays: 180,
            minimumLargeFileBytes: 250 * 1_024 * 1_024,
            minimumCacheBytes: 100 * 1_024 * 1_024,
            includeGeneralCaches: true,
            includeAppLeftovers: false,
            includeTrash: true,
            includeDeviceBackups: true,
            keepLatestSimulatorMinorPerMajor: true
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
