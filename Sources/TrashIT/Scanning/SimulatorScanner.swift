import Foundation

struct SimulatorScanner: CleanupScanning {
    let id = "simulators"

    private struct SimctlPayload: Decodable {
        let devices: [String: [Device]]?
    }

    private struct Device: Decodable {
        let dataPath: String?
        let dataPathSize: Int64?
        let isAvailable: Bool?
        let lastBootedAt: String?
        let name: String
        let state: String?
        let udid: String
    }

    struct RuntimeImage: Decodable, Sendable {
        let build: String?
        let deletable: Bool?
        let identifier: String
        let kind: String?
        let lastUsedAt: String?
        let platformIdentifier: String?
        let runtimeBundlePath: String?
        let runtimeIdentifier: String?
        let sizeBytes: Int64?
        let state: String?
        let version: String?
    }

    func scan(settings: ScannerSettings) async -> ScanResult {
        let budget = ScanBudget(seconds: 18)
        var result = ScanResult()
        var inUseRuntimeIdentifiers = Set<String>()

        do {
            let output = try ProcessRunner.runSimctl(arguments: ["list", "-j"])
            if output.status == 0 {
                let payload = try JSONDecoder().decode(SimctlPayload.self, from: output.stdout)
                let groups = payload.devices ?? [:]
                inUseRuntimeIdentifiers = Set(groups.compactMap { runtime, devices in
                    devices.contains { $0.state?.lowercased() == "booted" } ? runtime : nil
                })
                result.items.append(contentsOf: deviceItems(groups, settings: settings, budget: budget))
            } else {
                result.issues.append(
                    ScanIssue(scanner: id, message: "Simulator tools are unavailable. Install or select a full Xcode installation.")
                )
            }
        } catch {
            result.issues.append(ScanIssue(scanner: id, message: "Simulator devices could not be read: \(error.localizedDescription)"))
        }

        if !budget.isExpired {
            do {
                let output = try ProcessRunner.runSimctl(arguments: ["runtime", "list", "-v", "-j"])
                if output.status == 0 {
                    let images = try JSONDecoder().decode([String: RuntimeImage].self, from: output.stdout)
                    result.items.append(contentsOf: runtimeItems(
                        Array(images.values),
                        inUseRuntimeIdentifiers: inUseRuntimeIdentifiers,
                        settings: settings,
                        budget: budget
                    ))
                } else {
                    result.issues.append(ScanIssue(scanner: id, message: "Installed runtime images could not be read."))
                }
            } catch {
                result.issues.append(ScanIssue(scanner: id, message: "Installed runtime images could not be read: \(error.localizedDescription)"))
            }
        }

        if budget.isExpired {
            result.issues.append(ScanIssue(scanner: id, message: "Simulator scan reached its 18-second limit. Partial results are shown."))
        }
        return result
    }

    private func deviceItems(
        _ groups: [String: [Device]],
        settings: ScannerSettings,
        budget: ScanBudget
    ) -> [CleanupItem] {
        groups.flatMap { runtimeIdentifier, devices in
            devices.compactMap { (device: Device) -> CleanupItem? in
                guard !budget.isExpired else { return nil }
                guard device.state?.lowercased() != "booted" else { return nil }
                let url = device.dataPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                if let url, !settings.includes(url) { return nil }
                let bytes = device.dataPathSize ?? url.map { FileInspection.allocatedSize(of: $0) } ?? 0
                let unavailable = device.isAvailable == false
                return CleanupItem(
                    name: device.name,
                    url: url,
                    category: .simulators,
                    safety: unavailable ? .regeneratable : .reviewRequired,
                    action: .deleteSimulatorDevice(udid: device.udid),
                    allocatedBytes: bytes,
                    lastUsed: parseISODate(device.lastBootedAt),
                    reason: unavailable ? "This simulator device is unavailable." : "This simulator device is currently shut down.",
                    consequence: "The device data and installed test apps will be removed. A fresh device can be created later.",
                    source: id,
                    recommendations: unavailable ? [.lowRisk] : [],
                    metadata: ["runtime": runtimeIdentifier, "udid": device.udid]
                )
            }
        }
    }

    func runtimeItems(
        _ images: [RuntimeImage],
        inUseRuntimeIdentifiers: Set<String> = [],
        settings: ScannerSettings = .defaults,
        budget: ScanBudget
    ) -> [CleanupItem] {
        let deletableImages = images.filter { $0.deletable != false }
        let knownImages = deletableImages.filter { runtimeFamilyKey($0) != nil }
        let latestByPlatformMajor = Dictionary(grouping: knownImages) { runtimeFamilyKey($0)! }
            .compactMapValues { group in
                group.max { lhs, rhs in
                    let comparison = compareVersions(lhs.version, rhs.version)
                    if comparison != .orderedSame { return comparison == .orderedAscending }
                    return (lhs.build ?? "") < (rhs.build ?? "")
                }?.identifier
            }

        return deletableImages.compactMap { runtime -> CleanupItem? in
            guard !budget.isExpired else { return nil }
            let url = runtime.runtimeBundlePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let url, !settings.includes(url) { return nil }
            let bytes = runtime.sizeBytes ?? url.map { FileInspection.allocatedSize(of: $0) } ?? 0
            let family = runtimeFamilyKey(runtime)
            let isLatest = family.flatMap { latestByPlatformMajor[$0] } == runtime.identifier
            let unavailable = runtime.state?.lowercased() != "ready"
            let isInUse = runtime.runtimeIdentifier.map(inUseRuntimeIdentifiers.contains) ?? false
            let isOutdated = family != nil && !unavailable && !isLatest && !isInUse
            var recommendations = Set<CleanupRecommendation>()
            if family != nil && unavailable && !isInUse {
                recommendations.insert(.lowRisk)
            }
            if isOutdated {
                recommendations.formUnion([.lowRisk, .outdatedSimulator])
            }
            let platformName = platformDisplayName(runtime.platformIdentifier)
            let version = runtime.version ?? "Unknown"
            let buildSuffix = runtime.build.map { " (\($0))" } ?? ""
            return CleanupItem(
                name: "\(platformName) \(version)\(buildSuffix)",
                url: url,
                category: .simulators,
                safety: .redownloadable,
                action: .deleteSimulatorRuntime(identifier: runtime.identifier),
                allocatedBytes: bytes,
                lastUsed: parseISODate(runtime.lastUsedAt),
                reason: runtimeReason(
                    platformName: platformName,
                    unavailable: unavailable,
                    isLatest: isLatest,
                    isInUse: isInUse,
                    hasKnownVersion: family != nil
                ),
                consequence: "Projects targeting this exact runtime cannot run until it is downloaded again.",
                source: id,
                recommendations: recommendations,
                metadata: [
                    "identifier": runtime.identifier,
                    "runtimeIdentifier": runtime.runtimeIdentifier ?? "Unknown",
                    "version": version,
                    "build": runtime.build ?? "Unknown",
                    "kind": runtime.kind ?? "Unknown",
                    "inUse": isInUse ? "true" : "false"
                ]
            )
        }
    }

    private func runtimeFamilyKey(_ runtime: RuntimeImage) -> String? {
        guard let platform = runtime.platformIdentifier,
              let major = versionParts(runtime.version)?.first else { return nil }
        return "\(platform)|\(major)"
    }

    private func runtimeReason(
        platformName: String,
        unavailable: Bool,
        isLatest: Bool,
        isInUse: Bool,
        hasKnownVersion: Bool
    ) -> String {
        if isInUse { return "A booted simulator is currently using this runtime." }
        if !hasKnownVersion { return "The runtime version could not be determined, so it is not recommended automatically." }
        if unavailable { return "This runtime image is not ready." }
        if isLatest { return "Newest installed \(platformName) runtime for this major OS version." }
        return "A newer \(platformName) runtime for this major OS version is installed."
    }

    private func platformDisplayName(_ identifier: String?) -> String {
        switch identifier {
        case "com.apple.platform.iphonesimulator": "iOS"
        case "com.apple.platform.watchsimulator": "watchOS"
        case "com.apple.platform.appletvsimulator": "tvOS"
        case "com.apple.platform.xrsimulator": "visionOS"
        default: "Simulator"
        }
    }

    private func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func versionParts(_ version: String?) -> [Int]? {
        guard let version, !version.isEmpty else { return nil }
        let parts = version.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : nil
    }

    private func compareVersions(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let left = versionParts(lhs) ?? []
        let right = versionParts(rhs) ?? []
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
