import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cleanup: "Cleanup"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .cleanup: "checklist"
        case .history: "clock.arrow.circlepath"
        }
    }
}

public struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var destination: SidebarDestination? = .overview
    @State private var cleanupRequest: CleanupNavigationRequest?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $destination) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                SidebarStatusView()
            }
        } detail: {
            Group {
                switch destination ?? .overview {
                case .overview:
                    OverviewView(
                        goToCleanup: { request in
                            cleanupRequest = request
                            destination = .cleanup
                        },
                        goToHistory: { destination = .history }
                    )
                case .cleanup: ReviewView(navigationRequest: $cleanupRequest)
                case .history: HistoryView()
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(model.state == .scanning || model.state == .cleaning)
            }
            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .task { await model.loadOnce() }
        .sheet(item: $model.latestReceipt) { receipt in
            CleanupResultView(receipt: receipt)
                .environmentObject(model)
        }
    }
}

private struct SidebarStatusView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.state == .scanning || model.state == .cleaning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.title).font(.caption).fontWeight(.medium)
                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var statusDetail: String {
        if model.state == .scanning, model.totalScanners > 0 {
            return "\(model.completedScanners) of \(model.totalScanners) checks · \(model.items.count) found"
        }
        return "\(model.items.count) suggestions"
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
