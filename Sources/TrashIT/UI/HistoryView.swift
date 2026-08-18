import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.receipts.isEmpty {
                ContentUnavailableView(
                    "No cleanup history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed cleanups will leave a local receipt here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.receipts) { receipt in
                            DisclosureGroup {
                                VStack(spacing: 8) {
                                    ForEach(receipt.entries) { entry in
                                        HStack {
                                            Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .foregroundStyle(entry.succeeded ? .green : .red)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.itemName).fontWeight(.medium)
                                                Text(entry.message).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(Formatting.bytes(entry.bytes)).font(.caption.monospacedDigit())
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(receipt.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.headline)
                                        Text("\(receipt.entries.count) items · \(receipt.failureCount) failed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Formatting.bytes(receipt.processedBytes))
                                        .font(.title3.monospacedDigit().bold())
                                }
                            }
                            .card()
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("Cleanup history")
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
