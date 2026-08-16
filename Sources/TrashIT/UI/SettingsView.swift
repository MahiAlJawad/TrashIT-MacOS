import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Scan folders") {
                ForEach(model.settings.scanRoots, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(url.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            model.removeScanFolder(url)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    chooseFolder()
                } label: {
                    Label("Add folder…", systemImage: "plus")
                }
                Text("Downloads is the default. TrashIT does not crawl your entire home folder unless you add it explicitly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Old and large files") {
                Stepper(value: oldDaysBinding, in: 30...1_825, step: 30) {
                    LabeledContent("Consider unused after", value: "\(model.settings.oldFileDays) days")
                }
                Picker("Minimum large-file size", selection: minimumFileBinding) {
                    Text("100 MB").tag(Int64(100 * 1_024 * 1_024))
                    Text("250 MB").tag(Int64(250 * 1_024 * 1_024))
                    Text("500 MB").tag(Int64(500 * 1_024 * 1_024))
                    Text("1 GB").tag(Int64(1_024 * 1_024 * 1_024))
                }
                Picker("Minimum cache size", selection: minimumCacheBinding) {
                    Text("50 MB").tag(Int64(50 * 1_024 * 1_024))
                    Text("100 MB").tag(Int64(100 * 1_024 * 1_024))
                    Text("250 MB").tag(Int64(250 * 1_024 * 1_024))
                    Text("500 MB").tag(Int64(500 * 1_024 * 1_024))
                }
            }

            Section("Categories") {
                Toggle("Large application caches", isOn: settingBinding(\.includeGeneralCaches))
                Toggle("Review Trash contents", isOn: settingBinding(\.includeTrash))
                Toggle("Review iPhone and iPad backups", isOn: settingBinding(\.includeDeviceBackups))
                Toggle("Keep only the latest simulator minor per major", isOn: settingBinding(\.keepLatestSimulatorMinorPerMajor))
                Toggle("Experimental application-leftover detection", isOn: settingBinding(\.includeAppLeftovers))
                Text("App leftovers are only suggestions and are marked potentially irreplaceable. They are never preselected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Full Disk Access")
                        Text("macOS may still block protected folders. TrashIT works with partial access and reports skipped areas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open System Settings") { model.openFullDiskAccessSettings() }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save and scan again") {
                        Task { await model.scan() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
        .navigationTitle("Settings")
    }

    private var oldDaysBinding: Binding<Int> {
        Binding(get: { model.settings.oldFileDays }, set: { model.settings.oldFileDays = $0 })
    }

    private var minimumFileBinding: Binding<Int64> {
        Binding(get: { model.settings.minimumLargeFileBytes }, set: { model.settings.minimumLargeFileBytes = $0 })
    }

    private var minimumCacheBinding: Binding<Int64> {
        Binding(get: { model.settings.minimumCacheBytes }, set: { model.settings.minimumCacheBytes = $0 })
    }

    private func settingBinding(_ keyPath: WritableKeyPath<ScannerSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0 }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Scan"
        if panel.runModal() == .OK {
            panel.urls.forEach(model.addScanFolder)
        }
    }
}
