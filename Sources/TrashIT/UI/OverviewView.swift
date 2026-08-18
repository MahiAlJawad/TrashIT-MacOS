import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let goToCleanup: (CleanupNavigationRequest) -> Void
    let goToHistory: () -> Void

    private var groupedItems: [(CleanupCategory, [CleanupItem])] {
        Dictionary(grouping: model.items, by: \CleanupItem.category)
            .map { ($0.key, $0.value) }
            .sorted { bytes(in: $0.1) > bytes(in: $1.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryGrid
                categoryGrid
                if let issues = model.snapshot?.issues, !issues.isEmpty { issuesCard(issues) }
            }
            .padding(28)
        }
        .navigationTitle("TrashIT")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Make room without guessing").font(.largeTitle.bold())
                Text("A scan never selects anything. Choose a recommendation when you are ready.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                goToCleanup(CleanupNavigationRequest())
            } label: {
                Label("Review \(model.items.count) items", systemImage: "checklist")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.items.isEmpty)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 14)], spacing: 14) {
            summaryButton(
                title: "Cleaned so far",
                value: Formatting.bytes(model.cleanedSoFarBytes),
                detail: "Successful cleanups recorded on this Mac",
                symbol: "clock.arrow.circlepath",
                tint: .green,
                action: goToHistory
            )
            summaryButton(
                title: "Safe to delete",
                value: Formatting.bytes(model.safeToCleanBytes),
                detail: "Regenerable or re-downloadable recommendations",
                symbol: "checkmark.shield.fill",
                tint: .blue,
                action: {
                    goToCleanup(CleanupNavigationRequest(smartSelection: .safeCleanup))
                }
            )
            availableStorageCard
        }
    }

    private func summaryButton(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
                Text(value)
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                HStack {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var availableStorageCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Available storage", systemImage: "internaldrive.fill").font(.headline)
            if let capacity = model.capacity {
                Text(Formatting.bytes(capacity.available))
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                ProgressView(value: capacity.usedFraction)
                    .tint(capacity.usedFraction > 0.9 ? .red : .accentColor)
                Text("\(Formatting.bytes(capacity.used)) used of \(Formatting.bytes(capacity.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Capacity unavailable").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup categories").font(.title2.bold())
            Text("Open a category to review it. Only its recommended items will be selected.")
                .font(.callout)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(groupedItems, id: \.0) { category, items in
                    Button {
                        goToCleanup(CleanupNavigationRequest(category: category))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbolName)
                                .font(.title2)
                                .foregroundStyle(category.color)
                                .frame(width: 34, height: 34)
                                .background(category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.title).fontWeight(.medium).foregroundStyle(.primary)
                                Text("\(items.count) items · \(Formatting.bytes(bytes(in: items)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
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

    private func bytes(in items: [CleanupItem]) -> Int64 {
        items.reduce(0) { $0 + $1.allocatedBytes }
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
// SPDX-License-Identifier: GPL-3.0-or-later
