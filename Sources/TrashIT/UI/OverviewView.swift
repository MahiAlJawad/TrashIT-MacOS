import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let goToReview: () -> Void

    private var groupedItems: [(CleanupCategory, [CleanupItem])] {
        Dictionary(grouping: model.items, by: \CleanupItem.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.1.reduce(0) { $0 + $1.allocatedBytes } > $1.1.reduce(0) { $0 + $1.allocatedBytes } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                storageSummary
                targetCard
                categoryGrid
                if let issues = model.snapshot?.issues, !issues.isEmpty {
                    issuesCard(issues)
                }
            }
            .padding(28)
        }
        .navigationTitle("TrashIT")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Make room without guessing")
                    .font(.largeTitle.bold())
                Text("Every suggestion includes its risk and recovery cost.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                goToReview()
            } label: {
                Label("Review \(model.items.count) items", systemImage: "checklist")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.items.isEmpty)
        }
    }

    private var storageSummary: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Mac storage", systemImage: "internaldrive.fill")
                    .font(.headline)
                if let capacity = model.capacity {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Formatting.bytes(capacity.available)).font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("available").foregroundStyle(.secondary)
                    }
                    ProgressView(value: capacity.usedFraction)
                        .tint(capacity.usedFraction > 0.9 ? .red : .accentColor)
                    Text("\(Formatting.bytes(capacity.used)) used of \(Formatting.bytes(capacity.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Capacity unavailable").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Found by TrashIT", systemImage: "sparkles")
                    .font(.headline)
                Text(Formatting.bytes(model.totalFoundBytes))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Across \(model.items.count) reviewable items")
                    .foregroundStyle(.secondary)
                Text("Found size is an estimate; snapshots and Trash can delay actual recovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Low-disruption target").font(.headline)
                    Text("Choose regeneratable and re-downloadable items first.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(model.reclaimTargetGB)) GB")
                    .font(.title2.monospacedDigit().bold())
            }
            Slider(value: $model.reclaimTargetGB, in: 1...100, step: 1)
            HStack {
                SafetyBadge(level: .regeneratable)
                SafetyBadge(level: .redownloadable)
                Spacer()
                Button("Select safest items") {
                    model.selectSafestForTarget()
                    goToReview()
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
    }

    @ViewBuilder
    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup categories").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(groupedItems, id: \.0) { category, items in
                    HStack(spacing: 12) {
                        Image(systemName: category.symbolName)
                            .font(.title2)
                            .foregroundStyle(category.color)
                            .frame(width: 34, height: 34)
                            .background(category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title).fontWeight(.medium)
                            Text("\(items.count) items · \(Formatting.bytes(items.reduce(0) { $0 + $1.allocatedBytes }))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .card()
                }
            }
        }
    }

    private func issuesCard(_ issues: [ScanIssue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Some areas could not be scanned", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(issues) { issue in
                Text("• \(issue.message)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel

    var body: some View {
        Text(level.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(level.color)
            .background(level.color.opacity(0.12), in: Capsule())
    }
}
