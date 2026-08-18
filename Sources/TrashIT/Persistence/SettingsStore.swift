import Foundation

enum SettingsStore {
    private static let key = "TrashIT.ScannerSettings"

    static func load() -> ScannerSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ScannerSettings.self, from: data) else {
            return .defaults
        }
        #if TRASHIT_APP_STORE
        var sandboxSettings = settings
        sandboxSettings.scanRoots = SecurityScopedAccess.restoreAll()
        return sandboxSettings
        #else
        return settings
        #endif
    }

    static func save(_ settings: ScannerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
