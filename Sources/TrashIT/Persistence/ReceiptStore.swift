import Foundation

actor ReceiptStore {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.directory = support.appendingPathComponent("TrashIT/Receipts", isDirectory: true)
        }
    }

    func save(_ receipt: CleanupReceipt) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        try data.write(to: directory.appendingPathComponent("\(receipt.id.uuidString).json"), options: .atomic)
    }

    func loadAll() -> [CleanupReceipt] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(CleanupReceipt.self, from: data)
        }.sorted { $0.finishedAt > $1.finishedAt }
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
