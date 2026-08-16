import SwiftUI

@main
struct TrashITApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1_040, minHeight: 680)
                .onDisappear {
                    NSApplication.shared.terminate(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 620, height: 590)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
