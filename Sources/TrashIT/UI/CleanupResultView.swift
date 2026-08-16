import SwiftUI

struct CleanupResultView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let receipt: CleanupReceipt

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: receipt.failureCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(receipt.failureCount == 0 ? .green : .orange)
                Text(receipt.failureCount == 0 ? "Cleanup finished" : "Cleanup finished with issues")
                    .font(.title2.bold())
                Text(summary)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            List {
                ForEach(receipt.entries, id: \.id) { (entry: CleanupReceipt.Entry) in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(entry.succeeded ? .green : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.itemName).fontWeight(.medium)
                                Spacer()
                                Text(Formatting.bytes(entry.bytes))
                                    .font(.caption.monospacedDigit())
                            }
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(entry.succeeded ? Color.secondary : Color.red)
                            if let path = entry.originalPath {
                                Text(path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            HStack {
                if receipt.binCount > 0 {
                    Button("Open Bin") { model.openBin() }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    private var summary: String {
        var parts: [String] = []
        if receipt.binCount > 0 {
            parts.append("\(receipt.binCount) item(s) totaling \(Formatting.bytes(receipt.binBytes)) moved to Bin")
        }
        let otherSuccesses = receipt.successCount - receipt.binCount
        if otherSuccesses > 0 {
            parts.append("\(otherSuccesses) system action(s) completed")
        }
        if receipt.failureCount > 0 {
            parts.append("\(receipt.failureCount) item(s) failed")
        }
        let result = parts.joined(separator: "; ") + "."
        if receipt.binCount > 0 {
            return result + " Storage is reclaimed only after you empty Bin."
        }
        return result
    }
}
