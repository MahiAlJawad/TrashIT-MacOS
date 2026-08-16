import Foundation

enum SettingsStore {
    private static let key = "TrashIT.ScannerSettings"

    static func load() -> ScannerSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ScannerSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    static func save(_ settings: ScannerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
