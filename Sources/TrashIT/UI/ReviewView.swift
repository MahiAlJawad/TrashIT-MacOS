import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel

    @State private var query = ""
    @State private var safetyFilter: SafetyLevel?
    @State private var categoryFilter: CleanupCategory?
    @State private var showConfirmation = false

    private var displayedItems: [CleanupItem] {
        model.items.filter { item in
            let categoryMatches = categoryFilter.map { $0 == item.category } ?? true
            let safetyMatches = safetyFilter.map { $0 == item.safety } ?? true
            let queryMatches = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.reason.localizedCaseInsensitiveContains(query)
                || item.url?.path.localizedCaseInsensitiveContains(query) == true
            return categoryMatches && safetyMatches && queryMatches
        }
    }

    private var availableCategories: [CleanupCategory] {
        Array(Set(model.items.map(\.category))).sorted { $0.title < $1.title }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if displayedItems.isEmpty {
                ContentUnavailableView(
                    model.state == .scanning ? "Scanning…" : "Nothing to review",
                    systemImage: model.state == .scanning ? "magnifyingglass" : "checkmark.circle",
                    description: Text(model.state == .scanning ? "TrashIT is checking known safe locations." : "Try changing the filter or adding a scan folder.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedItems) { item in
                            CleanupItemRow(item: item)
                        }
                    }
                    .padding(20)
                }
            }
            Divider()
            selectionBar
        }
        .navigationTitle("Cleanup")
        .alert("Clean selected items?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean \(model.selectedItems.count) items", role: .destructive) {
                Task { await model.cleanSelected() }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            TextField("Search suggestions", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 330)
            Picker("Risk", selection: $safetyFilter) {
                Text("All safety levels").tag(SafetyLevel?.none)
                ForEach(SafetyLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(Optional(level))
                }
            }
            .frame(width: 190)
            Picker("Category", selection: $categoryFilter) {
                Text("All categories").tag(CleanupCategory?.none)
                ForEach(availableCategories) { category in
                    Text(category.title).tag(Optional(category))
                }
            }
            .frame(width: 180)
            Spacer()
            Button("Select visible") {
                let allowed = displayedItems.filter { $0.safety != .irreplaceable }.map(\.id)
                model.selectedIDs.formUnion(allowed)
            }
            Button("Clear") { model.clearSelection() }
        }
        .padding(16)
    }

    private var selectionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.selectedItems.count) selected")
                    .font(.headline)
                Text("Up to \(Formatting.bytes(model.selectedBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.selectedItems.contains(where: { $0.safety == .irreplaceable }) {
                Label("Includes potentially irreplaceable data", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                showConfirmation = true
            } label: {
                Label("Clean selected", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.selectedItems.isEmpty || model.state == .cleaning)
        }
        .padding(16)
        .background(.bar)
    }

    private var confirmationMessage: String {
        let permanent = model.selectedItems.filter { $0.action == .deletePermanently }.count
        let binItems = model.selectedItems.filter { $0.action.usesBin }.count
        let systemItems = model.selectedItems.count - permanent - binItems
        if permanent > 0 {
            return "\(binItems) item(s) will move to Bin, \(permanent) item(s) already in Bin will be permanently deleted, and \(systemItems) system action(s) will run. Estimated selection: \(Formatting.bytes(model.selectedBytes))."
        }
        return "\(binItems) filesystem item(s) will move to Bin. \(systemItems) simulator, Docker, or cloud action(s) cannot use Bin. Estimated selection: \(Formatting.bytes(model.selectedBytes))."
    }
}

private struct CleanupItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: CleanupItem

    private var selected: Bool { model.selectedIDs.contains(item.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { model.toggle(item) } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? item.safety.color : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "Deselect \(item.name)" : "Select \(item.name)")

            Image(systemName: item.category.symbolName)
                .font(.title2)
                .foregroundStyle(item.category.color)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.name).font(.headline).lineLimit(1)
                    SafetyBadge(level: item.safety)
                    Text(item.action.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatting.bytes(item.allocatedBytes))
                        .font(.headline.monospacedDigit())
                }
                Text(item.reason).font(.callout)
                Text(item.consequence).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let path = item.url?.path {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("Last used: \(Formatting.relativeDate(item.lastUsed))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.url != nil {
                        Button("Reveal") { model.reveal(item) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(15)
        .background(selected ? item.safety.color.opacity(0.06) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(selected ? item.safety.color.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.7)
        }
    }
}
