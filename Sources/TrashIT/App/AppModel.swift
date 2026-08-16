import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
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
    @Published var reclaimTargetGB: Double = 10
    @Published var completedScanners = 0
    @Published var totalScanners = 0
    @Published var settings: ScannerSettings {
        didSet { SettingsStore.save(settings) }
    }

    private let scanner = StorageScanner()
    private let receiptStore: ReceiptStore
    private let cleanupEngine: CleanupEngine
    private var hasLoaded = false

    init() {
        let receiptStore = ReceiptStore()
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
        let items = ((existing?.items ?? []) + result.items).sorted {
            if $0.safety != $1.safety { return $0.safety < $1.safety }
            return $0.allocatedBytes > $1.allocatedBytes
        }
        let issues = (existing?.issues ?? []) + result.issues
        snapshot = ScanSnapshot(date: Date(), items: items, issues: issues)
        selectedIDs.formUnion(result.items.filter(\.defaultSelected).map(\.id))
    }

    func toggle(_ item: CleanupItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectSafestForTarget() {
        let target = Int64(reclaimTargetGB * 1_000_000_000)
        var chosen = Set<UUID>()
        var bytes: Int64 = 0
        let candidates = items
            .filter { $0.safety <= .redownloadable && $0.metadata["keepRecommended"] != "true" }
            .sorted {
                if $0.safety != $1.safety { return $0.safety < $1.safety }
                return $0.allocatedBytes > $1.allocatedBytes
            }
        for item in candidates where bytes < target {
            chosen.insert(item.id)
            bytes += item.allocatedBytes
        }
        selectedIDs = chosen
    }

    func selectAll(in categories: Set<CleanupCategory>? = nil) {
        let candidates = categories.map { categories in items.filter { categories.contains($0.category) } } ?? items
        selectedIDs.formUnion(candidates.filter { $0.safety != .irreplaceable }.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func cleanSelected() async {
        let candidates = selectedItems
        guard !candidates.isEmpty, state != .cleaning else { return }
        state = .cleaning
        let receipt = await cleanupEngine.clean(candidates)
        latestReceipt = receipt
        receipts = await receiptStore.loadAll()
        selectedIDs.removeAll()
        capacity = VolumeCapacity.current()
        state = .ready
        await scan()
    }

    func addScanFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !settings.scanRoots.contains(normalized) else { return }
        settings.scanRoots.append(normalized)
    }

    func removeScanFolder(_ url: URL) {
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
