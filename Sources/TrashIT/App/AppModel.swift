import Foundation
import AppKit

@MainActor
public final class AppModel: ObservableObject {
    enum ScanState: Equatable {
        case idle
        case scanning
        case cleaning
        case ready

        var title: String {
            switch self {
            case .idle: "Ready to scan"
            case .scanning: "Scanning safely…"
            case .cleaning: "Cleaning selected items…"
            case .ready: "Scan complete"
            }
        }
    }

    @Published var state: ScanState = .idle
    @Published var snapshot: ScanSnapshot?
    @Published var selectedIDs = Set<UUID>()
    @Published var capacity = VolumeCapacity.current()
    @Published var receipts: [CleanupReceipt] = []
    @Published var latestReceipt: CleanupReceipt?
    @Published var errorMessage: String?
    @Published var activeSmartSelection: SmartSelectionRule?
    @Published var completedScanners = 0
    @Published var totalScanners = 0
    @Published var settings: ScannerSettings {
        didSet { SettingsStore.save(settings) }
    }

    private let scanner: StorageScanner
    private let receiptStore: ReceiptStore
    private let cleanupEngine: CleanupEngine
    private var hasLoaded = false

    public convenience init() {
        self.init(scanner: StorageScanner(), receiptStore: ReceiptStore())
    }

    init(scanner: StorageScanner, receiptStore: ReceiptStore) {
        self.scanner = scanner
        self.receiptStore = receiptStore
        self.cleanupEngine = CleanupEngine(receiptStore: receiptStore)
        self.settings = SettingsStore.load()
    }

    var items: [CleanupItem] { snapshot?.items ?? [] }

    var selectedItems: [CleanupItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.allocatedBytes }
    }

    var totalFoundBytes: Int64 { snapshot?.totalBytes ?? 0 }

    var cleanedSoFarBytes: Int64 {
        receipts.reduce(0) { $0 + $1.processedBytes }
    }

    var safeToCleanBytes: Int64 {
        items
            .filter { $0.recommendations.contains(.lowRisk) }
            .reduce(0) { $0 + $1.allocatedBytes }
    }

    func loadOnce() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        receipts = await receiptStore.loadAll()
        await scan()
    }

    func scan() async {
        guard state != .scanning && state != .cleaning else { return }
        state = .scanning
        completedScanners = 0
        totalScanners = 0
        snapshot = ScanSnapshot(date: Date(), items: [], issues: [])
        selectedIDs.removeAll()
        activeSmartSelection = nil
        defer {
            capacity = VolumeCapacity.current()
            if state == .scanning { state = .ready }
        }

        let stream = await scanner.progressStream(settings: settings)
        for await progress in stream {
            completedScanners = progress.completedScanners
            totalScanners = progress.totalScanners
            merge(progress.result)
        }

    }

    private func merge(_ result: ScanResult) {
        let existing = snapshot
        let includedItems = result.items.filter { item in
            item.url.map(settings.includes) ?? true
        }
        let combined = (existing?.items ?? []) + includedItems
        var seenLocations = Set<String>()
        let uniqueItems = combined.filter { item in
            let key = item.url?.standardizedFileURL.path ?? "\(item.source):\(item.id.uuidString)"
            return seenLocations.insert(key).inserted
        }
        let items = uniqueItems.sorted {
            if $0.safety != $1.safety { return $0.safety < $1.safety }
            return $0.allocatedBytes > $1.allocatedBytes
        }
        let issues = (existing?.issues ?? []) + result.issues
        snapshot = ScanSnapshot(date: Date(), items: items, issues: issues)
    }

    func toggle(_ item: CleanupItem) {
        activeSmartSelection = nil
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func applySmartSelection(_ rule: SmartSelectionRule) {
        selectedIDs = Set(items
            .filter { $0.recommendations.contains(rule.recommendation) }
            .map(\.id))
        activeSmartSelection = rule
    }

    func selectRecommended(in category: CleanupCategory) {
        selectedIDs = Set(items
            .filter { $0.category == category && !$0.recommendations.isEmpty }
            .map(\.id))
        activeSmartSelection = nil
    }

    func selectAll(in categories: Set<CleanupCategory>? = nil) {
        let candidates = categories.map { categories in items.filter { categories.contains($0.category) } } ?? items
        selectedIDs.formUnion(candidates.filter { $0.safety != .irreplaceable }.map(\.id))
        activeSmartSelection = nil
    }

    func select(_ candidates: [CleanupItem]) {
        selectedIDs.formUnion(candidates.filter { $0.safety != .irreplaceable }.map(\.id))
        activeSmartSelection = nil
    }

    func clearSelection() {
        selectedIDs.removeAll()
        activeSmartSelection = nil
    }

    func exclude(_ item: CleanupItem) {
        guard let url = item.url else { return }
        let normalized = url.standardizedFileURL
        if !settings.excludedPaths.contains(normalized) {
            settings.excludedPaths.append(normalized)
        }
        selectedIDs.remove(item.id)
        activeSmartSelection = nil
        if let snapshot {
            self.snapshot = ScanSnapshot(
                date: snapshot.date,
                items: snapshot.items.filter { $0.id != item.id },
                issues: snapshot.issues
            )
        }
    }

    func removeExcludedPath(_ url: URL) {
        settings.excludedPaths.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    }

    func cleanSelected() async {
        let candidates = selectedItems
        guard !candidates.isEmpty, state != .cleaning else { return }
        state = .cleaning
        let receipt = await cleanupEngine.clean(candidates)
        latestReceipt = receipt
        receipts = await receiptStore.loadAll()
        selectedIDs.removeAll()
        activeSmartSelection = nil
        capacity = VolumeCapacity.current()
        state = .ready
        await scan()
    }

    func addScanFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !settings.scanRoots.contains(normalized) else { return }
        SecurityScopedAccess.remember(normalized)
        settings.scanRoots.append(normalized)
    }

    func removeScanFolder(_ url: URL) {
        SecurityScopedAccess.forget(url)
        settings.scanRoots.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    }

    func reveal(_ item: CleanupItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openBin() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true))
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
