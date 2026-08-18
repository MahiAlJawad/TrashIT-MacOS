import Foundation

enum SafetyPolicyError: LocalizedError {
    case missingURL
    case outsideHome
    case protectedLocation(String)
    case symbolicLink
    case unsafeDirectDeletion
    case invalidIdentifier
    case cloudCopyNotSafe
    case applicationRunning(String)
    case unavailableInThisEdition

    var errorDescription: String? {
        switch self {
        case .missingURL: "The cleanup item has no file location."
        case .outsideHome: "TrashIT only removes files inside the current user’s home folder."
        case .protectedLocation(let path): "Protected location rejected: \(path)"
        case .symbolicLink: "Symbolic links are not removed by TrashIT."
        case .unsafeDirectDeletion: "Direct deletion is not allowed for this category."
        case .invalidIdentifier: "The simulator identifier is invalid."
        case .cloudCopyNotSafe: "The cloud copy is not fully uploaded or is currently changing."
        case .applicationRunning(let name): "Quit \(name) before cleaning its cache."
        case .unavailableInThisEdition: "This cleanup action is unavailable in the sandboxed App Store edition."
        }
    }
}

enum SafetyPolicy {
    private static let directDeletionCategories: Set<CleanupCategory> = [
        .xcode, .simulators, .developerCaches, .appCaches, .logs, .trash
    ]

    private static let protectedRelativePaths = [
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Safari",
        "Library/Accounts",
        "Library/Calendars",
        "Library/AddressBook"
    ]

    static func validate(_ item: CleanupItem) throws {
        #if TRASHIT_APP_STORE
        switch item.action {
        case .deleteSimulatorDevice, .deleteSimulatorRuntime, .pruneDocker, .cleanToolCache:
            throw SafetyPolicyError.unavailableInThisEdition
        default:
            break
        }
        #endif
        switch item.action {
        case .deleteSimulatorDevice(let udid):
            guard udid.range(of: #"^[A-Fa-f0-9-]{8,64}$"#, options: .regularExpression) != nil else {
                throw SafetyPolicyError.invalidIdentifier
            }
            return
        case .deleteSimulatorRuntime(let identifier):
            guard identifier.range(
                of: #"^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$"#,
                options: .regularExpression
            ) != nil else {
                throw SafetyPolicyError.invalidIdentifier
            }
            return
        case .pruneDocker:
            return
        case .cleanToolCache:
            guard item.category == .developerCaches else {
                throw SafetyPolicyError.unsafeDirectDeletion
            }
        case .deleteRegeneratable:
            guard directDeletionCategories.contains(item.category) else {
                throw SafetyPolicyError.unsafeDirectDeletion
            }
        case .deletePermanently:
            guard item.category == .trash else {
                throw SafetyPolicyError.unsafeDirectDeletion
            }
        case .moveToTrash, .evictCloudCopy:
            break
        }

        guard let url = item.url else { throw SafetyPolicyError.missingURL }
        guard !FileInspection.isSymbolicLink(url) else { throw SafetyPolicyError.symbolicLink }

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate.path.hasPrefix(home.path + "/") else {
            throw SafetyPolicyError.outsideHome
        }

        for relativePath in protectedRelativePaths {
            let protected = home.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            if candidate.path == protected.path || candidate.path.hasPrefix(protected.path + "/") {
                throw SafetyPolicyError.protectedLocation(candidate.path)
            }
        }

        if item.action == .evictCloudCopy {
            let values = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
                .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey
            ])
            guard values.isUbiquitousItem == true,
                  values.ubiquitousItemIsUploaded == true,
                  values.ubiquitousItemIsUploading != true,
                  values.ubiquitousItemUploadingError == nil else {
                throw SafetyPolicyError.cloudCopyNotSafe
            }
        }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
